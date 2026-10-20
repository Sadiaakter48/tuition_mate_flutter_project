import { createHash, randomBytes } from "node:crypto";
import { initializeApp } from "firebase-admin/app";
import {
  FieldValue,
  getFirestore,
  Timestamp,
} from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { defineSecret } from "firebase-functions/params";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { onDocumentWritten } from "firebase-functions/v2/firestore";

initializeApp();
const db = getFirestore();

const resendKey = defineSecret("RESEND_API_KEY");
const emailFrom = defineSecret("RESEND_FROM");
const twilioSid = defineSecret("TWILIO_ACCOUNT_SID");
const twilioToken = defineSecret("TWILIO_AUTH_TOKEN");
const twilioFrom = defineSecret("TWILIO_FROM");
const whatsappToken = defineSecret("WHATSAPP_TOKEN");
const whatsappPhoneId = defineSecret("WHATSAPP_PHONE_NUMBER_ID");
const whatsappTemplate = defineSecret("WHATSAPP_TEMPLATE_NAME");
const allSecrets = [
  resendKey,
  emailFrom,
  twilioSid,
  twilioToken,
  twilioFrom,
  whatsappToken,
  whatsappPhoneId,
  whatsappTemplate,
];

type Student = {
  id: string;
  name?: string;
  guardianName?: string;
  guardianEmail?: string;
  guardianPhone?: string;
  guardianUid?: string;
  phone?: string;
  monthlyFee?: number;
  feeDueDay?: number;
  feePaid?: boolean;
  feePaidMonth?: string;
  attendance?: Record<string, boolean>;
};

type Message = {
  subject: string;
  text: string;
};

function requireAuth(request: { auth?: { uid: string; token: Record<string, unknown> } | null }): string {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign in is required.");
  }
  return request.auth.uid;
}

function monthKey(date: Date): string {
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}`;
}

function studentRef(teacherUid: string, studentId: string) {
  return db.doc(`users/${teacherUid}/students/${studentId}`);
}

async function workspaceFor(userUid: string): Promise<string> {
  const user = await db.doc(`users/${userUid}`).get();
  const profile = user.data();
  const workspaceId = profile?.workspaceId;
  if (profile?.role === "owner" && workspaceId === userUid) return userUid;
  if (profile?.role === "teacher" && typeof workspaceId === "string") {
    const membership = await db.doc(`users/${workspaceId}/members/${userUid}`).get();
    if (membership.data()?.active === true) return workspaceId;
  }
  throw new HttpsError("permission-denied", "This account has no active teaching workspace.");
}

async function readStudent(teacherUid: string, studentId: string): Promise<Student> {
  const snapshot = await studentRef(teacherUid, studentId).get();
  if (!snapshot.exists) {
    throw new HttpsError("not-found", "Student record was not found.");
  }
  return { id: snapshot.id, ...(snapshot.data() as Omit<Student, "id">) };
}

function destinationPhone(student: Student): string | undefined {
  return student.guardianPhone?.trim() || student.phone?.trim() || undefined;
}

async function sendEmail(to: string, message: Message): Promise<void> {
  if (!resendKey.value() || !emailFrom.value()) {
    throw new Error("Email provider is not configured (RESEND_API_KEY/RESEND_FROM).");
  }
  const response = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${resendKey.value()}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: emailFrom.value(),
      to: [to],
      subject: message.subject,
      text: message.text,
    }),
  });
  if (!response.ok) {
    throw new Error(`Resend returned ${response.status}: ${await response.text()}`);
  }
}

async function sendSms(to: string, message: Message): Promise<void> {
  if (!twilioSid.value() || !twilioToken.value() || !twilioFrom.value()) {
    throw new Error("SMS provider is not configured (Twilio secrets are missing).");
  }
  const authorization = Buffer.from(
    `${twilioSid.value()}:${twilioToken.value()}`,
  ).toString("base64");
  const response = await fetch(
    `https://api.twilio.com/2010-04-01/Accounts/${twilioSid.value()}/Messages.json`,
    {
      method: "POST",
      headers: {
        Authorization: `Basic ${authorization}`,
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body: new URLSearchParams({
        To: to,
        From: twilioFrom.value(),
        Body: `${message.subject}\n${message.text}`,
      }),
    },
  );
  if (!response.ok) {
    throw new Error(`Twilio returned ${response.status}: ${await response.text()}`);
  }
}

async function sendWhatsApp(to: string, message: Message): Promise<void> {
  if (!whatsappToken.value() || !whatsappPhoneId.value() || !whatsappTemplate.value()) {
    throw new Error("WhatsApp provider is not configured (Cloud API secrets are missing).");
  }
  const response = await fetch(
    `https://graph.facebook.com/v22.0/${whatsappPhoneId.value()}/messages`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${whatsappToken.value()}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        messaging_product: "whatsapp",
        to,
        type: "template",
        template: {
          name: whatsappTemplate.value(),
          language: { code: "en" },
          components: [{
            type: "body",
            parameters: [
              { type: "text", text: message.subject },
              { type: "text", text: message.text },
            ],
          }],
        },
      }),
    },
  );
  if (!response.ok) {
    throw new Error(`WhatsApp Cloud API returned ${response.status}: ${await response.text()}`);
  }
}

async function sendAllChannels(
  student: Student,
  message: Message,
  logRef: FirebaseFirestore.DocumentReference,
): Promise<void> {
  const phone = destinationPhone(student);
  const sends: Record<string, (() => Promise<void>) | undefined> = {
    email: student.guardianEmail?.trim()
      ? () => sendEmail(student.guardianEmail!.trim(), message)
      : undefined,
    sms: phone ? () => sendSms(phone, message) : undefined,
    whatsapp: phone ? () => sendWhatsApp(phone, message) : undefined,
  };
  const outcomes: Record<string, string> = {};
  for (const [channel, send] of Object.entries(sends)) {
    if (!send) {
      outcomes[channel] = "no-recipient";
      continue;
    }
    try {
      await send();
      outcomes[channel] = "sent";
    } catch (error) {
      outcomes[channel] = "failed";
      logger.error(`Reminder delivery failed via ${channel}.`, {
        studentId: student.id,
        error,
      });
    }
  }
  await logRef.set({
    studentId: student.id,
    channels: outcomes,
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });
  if (!Object.values(outcomes).includes("sent")) {
    throw new HttpsError(
      "failed-precondition",
      "No reminder channel succeeded. Check contacts and provider secrets.",
    );
  }
  if (Object.values(outcomes).includes("failed")) {
    throw new HttpsError(
      "unavailable",
      "Some reminder channels failed. Check the delivery log and provider configuration.",
    );
  }
}

export const createGuardianInvite = onCall(
  { secrets: [resendKey, emailFrom] },
  async (request) => {
  const requesterUid = requireAuth(request);
  const teacherUid = await workspaceFor(requesterUid);
  const studentId = request.data?.studentId;
  if (typeof studentId !== "string" || !studentId.trim()) {
    throw new HttpsError("invalid-argument", "A student ID is required.");
  }
  const student = await readStudent(teacherUid, studentId);
  const email = student.guardianEmail?.trim().toLowerCase();
  if (student.guardianUid) {
    throw new HttpsError("failed-precondition", "A guardian account is already linked to this student.");
  }
  if (!email) {
    throw new HttpsError(
      "failed-precondition",
      "Add the guardian's email to the student record before inviting them.",
    );
  }
  const rawCode = randomBytes(24).toString("base64url");
  const codeHash = createHash("sha256").update(rawCode).digest("hex");
  await db.doc(`guardianInvites/${codeHash}`).create({
    teacherUid,
    studentId,
    email,
    expiresAt: Timestamp.fromMillis(Date.now() + 7 * 24 * 60 * 60 * 1000),
    createdAt: FieldValue.serverTimestamp(),
  });
  try {
    await sendEmail(email, {
      subject: "Your TuitionMate family portal invitation",
      text: `Your teacher invited you to view ${student.name ?? "the student's"} tuition records.\n\nCreate a family portal account in TuitionMate with this one-time code:\n${rawCode}\n\nThis invitation expires in 7 days.`,
    });
  } catch (error) {
    await db.doc(`guardianInvites/${codeHash}`).delete();
    logger.error("Guardian invitation email could not be delivered.", {
      teacherUid,
      studentId,
      error,
    });
    throw new HttpsError("unavailable", "The invitation email could not be delivered. Check the email provider configuration.");
  }
  return { inviteCode: rawCode, expiresInDays: 7 };
});

export const createTeacherInvite = onCall(
  { secrets: [resendKey, emailFrom] },
  async (request) => {
    const ownerUid = requireAuth(request);
    const owner = await db.doc(`users/${ownerUid}`).get();
    if (owner.data()?.role !== "owner" || owner.data()?.workspaceId !== ownerUid) {
      throw new HttpsError("permission-denied", "Only the workspace owner can invite teachers.");
    }
    const email = String(request.data?.email ?? "").trim().toLowerCase();
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
      throw new HttpsError("invalid-argument", "Enter a valid teacher email.");
    }
    const rawCode = randomBytes(24).toString("base64url");
    const codeHash = createHash("sha256").update(rawCode).digest("hex");
    const inviteRef = db.doc(`teacherInvites/${codeHash}`);
    await inviteRef.create({
      ownerUid,
      email,
      expiresAt: Timestamp.fromMillis(Date.now() + 7 * 24 * 60 * 60 * 1000),
      createdAt: FieldValue.serverTimestamp(),
    });
    try {
      await sendEmail(email, {
        subject: "Invitation to join a TuitionMate teaching workspace",
        text: `The workspace owner invited you to join TuitionMate.\n\nCreate a teacher account with this one-time invitation code:\n${rawCode}\n\nThis invitation expires in 7 days.`,
      });
    } catch (error) {
      await inviteRef.delete();
      logger.error("Teacher invitation email could not be delivered.", {
        ownerUid,
        error,
      });
      throw new HttpsError("unavailable", "The invitation email could not be delivered. Check the email provider configuration.");
    }
    return { inviteCode: rawCode, expiresInDays: 7 };
  },
);

export const claimTeacherInvite = onCall(async (request) => {
  const teacherUid = requireAuth(request);
  const email = String(request.auth?.token.email ?? "").trim().toLowerCase();
  const rawCode = request.data?.inviteCode;
  if (typeof rawCode !== "string" || rawCode.length < 20 || !email) {
    throw new HttpsError("invalid-argument", "A valid invitation and email are required.");
  }
  const codeHash = createHash("sha256").update(rawCode).digest("hex");
  const inviteRef = db.doc(`teacherInvites/${codeHash}`);
  await db.runTransaction(async (transaction) => {
    const invite = await transaction.get(inviteRef);
    if (!invite.exists) {
      throw new HttpsError("not-found", "The invitation is invalid or already used.");
    }
    const details = invite.data()!;
    if ((details.expiresAt as Timestamp).toMillis() < Date.now()) {
      throw new HttpsError("deadline-exceeded", "The invitation has expired.");
    }
    if (details.email !== email) {
      throw new HttpsError("permission-denied", "Sign in with the invited teacher email.");
    }
    const owner = await transaction.get(db.doc(`users/${details.ownerUid}`));
    const existingProfile = await transaction.get(db.doc(`users/${teacherUid}`));
    if (!owner.exists || owner.data()?.role !== "owner") {
      throw new HttpsError("failed-precondition", "The workspace owner is unavailable.");
    }
    if (existingProfile.data()?.role) {
      throw new HttpsError("already-exists", "Use a new account for this teacher invitation.");
    }
    transaction.set(db.doc(`users/${details.ownerUid}/members/${teacherUid}`), {
      email,
      name: String(request.auth?.token.name ?? ""),
      active: true,
      createdAt: FieldValue.serverTimestamp(),
    });
    transaction.set(db.doc(`users/${teacherUid}`), {
      role: "teacher",
      workspaceId: details.ownerUid,
      email,
      name: String(request.auth?.token.name ?? ""),
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    transaction.delete(inviteRef);
  });
  return { joined: true };
});

export const claimGuardianInvite = onCall(async (request) => {
  const guardianUid = requireAuth(request);
  const email = String(request.auth?.token.email ?? "").trim().toLowerCase();
  const rawCode = request.data?.inviteCode;
  if (typeof rawCode !== "string" || rawCode.length < 20 || !email) {
    throw new HttpsError("invalid-argument", "A valid invitation and verified email are required.");
  }
  const codeHash = createHash("sha256").update(rawCode).digest("hex");
  const inviteRef = db.doc(`guardianInvites/${codeHash}`);
  await db.runTransaction(async (transaction) => {
    const invite = await transaction.get(inviteRef);
    if (!invite.exists) {
      throw new HttpsError("not-found", "The invitation is invalid or already used.");
    }
    const details = invite.data()!;
    if ((details.expiresAt as Timestamp).toMillis() < Date.now()) {
      throw new HttpsError("deadline-exceeded", "The invitation has expired.");
    }
    if (details.email !== email) {
      throw new HttpsError("permission-denied", "Sign in with the email the teacher invited.");
    }
    const student = await transaction.get(studentRef(details.teacherUid, details.studentId));
    const guardianProfile = await transaction.get(db.doc(`users/${guardianUid}`));
    const existingRole = guardianProfile.data()?.role;
    if (existingRole && existingRole !== "guardian") {
      throw new HttpsError("failed-precondition", "Use a separate account for the family portal.");
    }
    const existingTeacherUid = guardianProfile.data()?.linkedTeacherUid;
    if (existingTeacherUid && existingTeacherUid !== details.teacherUid) {
      throw new HttpsError("failed-precondition", "This family account is already linked to another workspace.");
    }
    if (!student.exists) {
      throw new HttpsError("not-found", "The invited student record no longer exists.");
    }
    transaction.update(student.ref, { guardianUid });
    transaction.set(db.doc(`users/${guardianUid}`), {
      role: "guardian",
      linkedTeacherUid: details.teacherUid,
      linkedStudentId: details.studentId,
      email,
      name: String(request.auth?.token.name ?? ""),
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    transaction.delete(inviteRef);
  });
  return { linked: true };
});

export const removeWorkspaceTeacher = onCall(async (request) => {
  const ownerUid = requireAuth(request);
  const owner = await db.doc(`users/${ownerUid}`).get();
  if (owner.data()?.role !== "owner" || owner.data()?.workspaceId !== ownerUid) {
    throw new HttpsError("permission-denied", "Only the workspace owner can remove teachers.");
  }
  const teacherUid = request.data?.teacherUid;
  if (typeof teacherUid !== "string" || !teacherUid || teacherUid === ownerUid) {
    throw new HttpsError("invalid-argument", "A valid teacher account is required.");
  }
  const membershipRef = db.doc(`users/${ownerUid}/members/${teacherUid}`);
  const teacherRef = db.doc(`users/${teacherUid}`);
  await db.runTransaction(async (transaction) => {
    const membership = await transaction.get(membershipRef);
    const teacher = await transaction.get(teacherRef);
    if (!membership.exists || teacher.data()?.workspaceId !== ownerUid) {
      throw new HttpsError("not-found", "The teacher is not a member of this workspace.");
    }
    transaction.delete(membershipRef);
    transaction.update(teacherRef, {
      role: "suspended",
      workspaceId: FieldValue.delete(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
  return { removed: true };
});

export const sendManualReminder = onCall({ secrets: allSecrets }, async (request) => {
  const requesterUid = requireAuth(request);
  const teacherUid = await workspaceFor(requesterUid);
  const studentId = request.data?.studentId;
  const type = request.data?.type;
  if (typeof studentId !== "string" || !["fee", "absence"].includes(type)) {
    throw new HttpsError("invalid-argument", "A student ID and valid reminder type are required.");
  }
  const student = await readStudent(teacherUid, studentId);
  const month = monthKey(new Date());
  const id = `manual-${type}-${studentId}-${Date.now()}`;
  const message: Message = type === "fee"
    ? {
      subject: "Tuition fee reminder",
      text: `${student.guardianName || "Guardian"}, ${student.name} has a tuition fee of ৳${student.monthlyFee ?? 0} due for ${month}.`,
    }
    : {
      subject: "Attendance update",
      text: `${student.name} was marked absent from a tuition class today. Please contact the teacher if this is unexpected.`,
    };
  await sendAllChannels(student, message, db.doc(`users/${teacherUid}/reminderLogs/${id}`));
  return { sent: true };
});

export const sendScheduledFeeReminders = onSchedule(
  {
    schedule: "0 8 * * *",
    timeZone: "Asia/Dhaka",
    secrets: allSecrets,
  },
  async () => {
    const today = new Date();
    const month = monthKey(today);
    const daysInMonth = new Date(today.getFullYear(), today.getMonth() + 1, 0).getDate();
    const currentDay = today.getDate();
    const users = await db.collection("users").where("role", "==", "owner").get();
    for (const teacher of users.docs) {
      const students = await teacher.ref.collection("students").get();
      for (const studentDoc of students.docs) {
        const student = { id: studentDoc.id, ...(studentDoc.data() as Omit<Student, "id">) };
        if (student.feePaidMonth === month) continue;
        const dueDay = Math.min(Math.max(student.feeDueDay ?? 1, 1), daysInMonth);
        const offset = dueDay - currentDay;
        if (![3, 0, -3].includes(offset)) continue;
        const key = `fee-${student.id}-${month}-${offset}`;
        const logRef = teacher.ref.collection("reminderLogs").doc(key);
        const existing = await logRef.get();
        if (existing.exists) continue;
        const phase = offset === 3 ? "due in 3 days" : offset === 0 ? "due today" : "3 days overdue";
        try {
          await sendAllChannels(
            student,
            {
              subject: "Tuition fee reminder",
              text: `${student.guardianName || "Guardian"}, the tuition fee of ৳${student.monthlyFee ?? 0} for ${student.name} is ${phase}.`,
            },
            logRef,
          );
        } catch (error) {
          logger.error("Scheduled fee reminder could not be delivered.", {
            teacherUid: teacher.id,
            studentId: student.id,
            error,
          });
          await logRef.set({
            studentId: student.id,
            error: String(error),
            updatedAt: FieldValue.serverTimestamp(),
          }, { merge: true });
        }
      }
    }
  },
);

export const notifyOnAbsence = onDocumentWritten(
  {
    document: "users/{teacherUid}/students/{studentId}",
    secrets: allSecrets,
  },
  async (event) => {
    const before = event.data?.before.data() as Student | undefined;
    const after = event.data?.after.data() as Student | undefined;
    if (!before || !after) return;
    const previous = before.attendance ?? {};
    const updated = after.attendance ?? {};
    const absentKeys = Object.entries(updated)
      .filter(([key, present]) => present === false && previous[key] !== false)
      .map(([key]) => key);
    for (const key of absentKeys) {
      const id = `absence-${event.params.studentId}-${createHash("sha1").update(key).digest("hex")}`;
      const logRef = db.doc(`users/${event.params.teacherUid}/reminderLogs/${id}`);
      try {
        await sendAllChannels(
          { ...after, id: event.params.studentId },
          {
            subject: "Attendance update",
            text: `${after.name ?? "The student"} was marked absent for the scheduled class. Please contact the teacher if this is unexpected.`,
          },
          logRef,
        );
      } catch (error) {
        logger.error("Absence notification could not be delivered.", {
          studentId: event.params.studentId,
          error,
        });
      }
    }
  },
);
