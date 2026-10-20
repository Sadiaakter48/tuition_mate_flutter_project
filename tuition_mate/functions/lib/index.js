"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.notifyOnAbsence = exports.sendScheduledFeeReminders = exports.sendManualReminder = exports.removeWorkspaceTeacher = exports.claimGuardianInvite = exports.claimTeacherInvite = exports.createTeacherInvite = exports.createGuardianInvite = void 0;
const node_crypto_1 = require("node:crypto");
const app_1 = require("firebase-admin/app");
const firestore_1 = require("firebase-admin/firestore");
const firebase_functions_1 = require("firebase-functions");
const params_1 = require("firebase-functions/params");
const https_1 = require("firebase-functions/v2/https");
const scheduler_1 = require("firebase-functions/v2/scheduler");
const firestore_2 = require("firebase-functions/v2/firestore");
(0, app_1.initializeApp)();
const db = (0, firestore_1.getFirestore)();
const resendKey = (0, params_1.defineSecret)("RESEND_API_KEY");
const emailFrom = (0, params_1.defineSecret)("RESEND_FROM");
const twilioSid = (0, params_1.defineSecret)("TWILIO_ACCOUNT_SID");
const twilioToken = (0, params_1.defineSecret)("TWILIO_AUTH_TOKEN");
const twilioFrom = (0, params_1.defineSecret)("TWILIO_FROM");
const whatsappToken = (0, params_1.defineSecret)("WHATSAPP_TOKEN");
const whatsappPhoneId = (0, params_1.defineSecret)("WHATSAPP_PHONE_NUMBER_ID");
const whatsappTemplate = (0, params_1.defineSecret)("WHATSAPP_TEMPLATE_NAME");
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
function requireAuth(request) {
    if (!request.auth) {
        throw new https_1.HttpsError("unauthenticated", "Sign in is required.");
    }
    return request.auth.uid;
}
function monthKey(date) {
    return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}`;
}
function studentRef(teacherUid, studentId) {
    return db.doc(`users/${teacherUid}/students/${studentId}`);
}
async function workspaceFor(userUid) {
    const user = await db.doc(`users/${userUid}`).get();
    const profile = user.data();
    const workspaceId = profile?.workspaceId;
    if (profile?.role === "owner" && workspaceId === userUid)
        return userUid;
    if (profile?.role === "teacher" && typeof workspaceId === "string") {
        const membership = await db.doc(`users/${workspaceId}/members/${userUid}`).get();
        if (membership.data()?.active === true)
            return workspaceId;
    }
    throw new https_1.HttpsError("permission-denied", "This account has no active teaching workspace.");
}
async function readStudent(teacherUid, studentId) {
    const snapshot = await studentRef(teacherUid, studentId).get();
    if (!snapshot.exists) {
        throw new https_1.HttpsError("not-found", "Student record was not found.");
    }
    return { id: snapshot.id, ...snapshot.data() };
}
function destinationPhone(student) {
    return student.guardianPhone?.trim() || student.phone?.trim() || undefined;
}
async function sendEmail(to, message) {
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
async function sendSms(to, message) {
    if (!twilioSid.value() || !twilioToken.value() || !twilioFrom.value()) {
        throw new Error("SMS provider is not configured (Twilio secrets are missing).");
    }
    const authorization = Buffer.from(`${twilioSid.value()}:${twilioToken.value()}`).toString("base64");
    const response = await fetch(`https://api.twilio.com/2010-04-01/Accounts/${twilioSid.value()}/Messages.json`, {
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
    });
    if (!response.ok) {
        throw new Error(`Twilio returned ${response.status}: ${await response.text()}`);
    }
}
async function sendWhatsApp(to, message) {
    if (!whatsappToken.value() || !whatsappPhoneId.value() || !whatsappTemplate.value()) {
        throw new Error("WhatsApp provider is not configured (Cloud API secrets are missing).");
    }
    const response = await fetch(`https://graph.facebook.com/v22.0/${whatsappPhoneId.value()}/messages`, {
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
    });
    if (!response.ok) {
        throw new Error(`WhatsApp Cloud API returned ${response.status}: ${await response.text()}`);
    }
}
async function sendAllChannels(student, message, logRef) {
    const phone = destinationPhone(student);
    const sends = {
        email: student.guardianEmail?.trim()
            ? () => sendEmail(student.guardianEmail.trim(), message)
            : undefined,
        sms: phone ? () => sendSms(phone, message) : undefined,
        whatsapp: phone ? () => sendWhatsApp(phone, message) : undefined,
    };
    const outcomes = {};
    for (const [channel, send] of Object.entries(sends)) {
        if (!send) {
            outcomes[channel] = "no-recipient";
            continue;
        }
        try {
            await send();
            outcomes[channel] = "sent";
        }
        catch (error) {
            outcomes[channel] = "failed";
            firebase_functions_1.logger.error(`Reminder delivery failed via ${channel}.`, {
                studentId: student.id,
                error,
            });
        }
    }
    await logRef.set({
        studentId: student.id,
        channels: outcomes,
        updatedAt: firestore_1.FieldValue.serverTimestamp(),
    }, { merge: true });
    if (!Object.values(outcomes).includes("sent")) {
        throw new https_1.HttpsError("failed-precondition", "No reminder channel succeeded. Check contacts and provider secrets.");
    }
    if (Object.values(outcomes).includes("failed")) {
        throw new https_1.HttpsError("unavailable", "Some reminder channels failed. Check the delivery log and provider configuration.");
    }
}
exports.createGuardianInvite = (0, https_1.onCall)({ secrets: [resendKey, emailFrom] }, async (request) => {
    const requesterUid = requireAuth(request);
    const teacherUid = await workspaceFor(requesterUid);
    const studentId = request.data?.studentId;
    if (typeof studentId !== "string" || !studentId.trim()) {
        throw new https_1.HttpsError("invalid-argument", "A student ID is required.");
    }
    const student = await readStudent(teacherUid, studentId);
    const email = student.guardianEmail?.trim().toLowerCase();
    if (student.guardianUid) {
        throw new https_1.HttpsError("failed-precondition", "A guardian account is already linked to this student.");
    }
    if (!email) {
        throw new https_1.HttpsError("failed-precondition", "Add the guardian's email to the student record before inviting them.");
    }
    const rawCode = (0, node_crypto_1.randomBytes)(24).toString("base64url");
    const codeHash = (0, node_crypto_1.createHash)("sha256").update(rawCode).digest("hex");
    await db.doc(`guardianInvites/${codeHash}`).create({
        teacherUid,
        studentId,
        email,
        expiresAt: firestore_1.Timestamp.fromMillis(Date.now() + 7 * 24 * 60 * 60 * 1000),
        createdAt: firestore_1.FieldValue.serverTimestamp(),
    });
    try {
        await sendEmail(email, {
            subject: "Your TuitionMate family portal invitation",
            text: `Your teacher invited you to view ${student.name ?? "the student's"} tuition records.\n\nCreate a family portal account in TuitionMate with this one-time code:\n${rawCode}\n\nThis invitation expires in 7 days.`,
        });
    }
    catch (error) {
        await db.doc(`guardianInvites/${codeHash}`).delete();
        firebase_functions_1.logger.error("Guardian invitation email could not be delivered.", {
            teacherUid,
            studentId,
            error,
        });
        throw new https_1.HttpsError("unavailable", "The invitation email could not be delivered. Check the email provider configuration.");
    }
    return { inviteCode: rawCode, expiresInDays: 7 };
});
exports.createTeacherInvite = (0, https_1.onCall)({ secrets: [resendKey, emailFrom] }, async (request) => {
    const ownerUid = requireAuth(request);
    const owner = await db.doc(`users/${ownerUid}`).get();
    if (owner.data()?.role !== "owner" || owner.data()?.workspaceId !== ownerUid) {
        throw new https_1.HttpsError("permission-denied", "Only the workspace owner can invite teachers.");
    }
    const email = String(request.data?.email ?? "").trim().toLowerCase();
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
        throw new https_1.HttpsError("invalid-argument", "Enter a valid teacher email.");
    }
    const rawCode = (0, node_crypto_1.randomBytes)(24).toString("base64url");
    const codeHash = (0, node_crypto_1.createHash)("sha256").update(rawCode).digest("hex");
    const inviteRef = db.doc(`teacherInvites/${codeHash}`);
    await inviteRef.create({
        ownerUid,
        email,
        expiresAt: firestore_1.Timestamp.fromMillis(Date.now() + 7 * 24 * 60 * 60 * 1000),
        createdAt: firestore_1.FieldValue.serverTimestamp(),
    });
    try {
        await sendEmail(email, {
            subject: "Invitation to join a TuitionMate teaching workspace",
            text: `The workspace owner invited you to join TuitionMate.\n\nCreate a teacher account with this one-time invitation code:\n${rawCode}\n\nThis invitation expires in 7 days.`,
        });
    }
    catch (error) {
        await inviteRef.delete();
        firebase_functions_1.logger.error("Teacher invitation email could not be delivered.", {
            ownerUid,
            error,
        });
        throw new https_1.HttpsError("unavailable", "The invitation email could not be delivered. Check the email provider configuration.");
    }
    return { inviteCode: rawCode, expiresInDays: 7 };
});
exports.claimTeacherInvite = (0, https_1.onCall)(async (request) => {
    const teacherUid = requireAuth(request);
    const email = String(request.auth?.token.email ?? "").trim().toLowerCase();
    const rawCode = request.data?.inviteCode;
    if (typeof rawCode !== "string" || rawCode.length < 20 || !email) {
        throw new https_1.HttpsError("invalid-argument", "A valid invitation and email are required.");
    }
    const codeHash = (0, node_crypto_1.createHash)("sha256").update(rawCode).digest("hex");
    const inviteRef = db.doc(`teacherInvites/${codeHash}`);
    await db.runTransaction(async (transaction) => {
        const invite = await transaction.get(inviteRef);
        if (!invite.exists) {
            throw new https_1.HttpsError("not-found", "The invitation is invalid or already used.");
        }
        const details = invite.data();
        if (details.expiresAt.toMillis() < Date.now()) {
            throw new https_1.HttpsError("deadline-exceeded", "The invitation has expired.");
        }
        if (details.email !== email) {
            throw new https_1.HttpsError("permission-denied", "Sign in with the invited teacher email.");
        }
        const owner = await transaction.get(db.doc(`users/${details.ownerUid}`));
        const existingProfile = await transaction.get(db.doc(`users/${teacherUid}`));
        if (!owner.exists || owner.data()?.role !== "owner") {
            throw new https_1.HttpsError("failed-precondition", "The workspace owner is unavailable.");
        }
        if (existingProfile.data()?.role) {
            throw new https_1.HttpsError("already-exists", "Use a new account for this teacher invitation.");
        }
        transaction.set(db.doc(`users/${details.ownerUid}/members/${teacherUid}`), {
            email,
            name: String(request.auth?.token.name ?? ""),
            active: true,
            createdAt: firestore_1.FieldValue.serverTimestamp(),
        });
        transaction.set(db.doc(`users/${teacherUid}`), {
            role: "teacher",
            workspaceId: details.ownerUid,
            email,
            name: String(request.auth?.token.name ?? ""),
            updatedAt: firestore_1.FieldValue.serverTimestamp(),
        }, { merge: true });
        transaction.delete(inviteRef);
    });
    return { joined: true };
});
exports.claimGuardianInvite = (0, https_1.onCall)(async (request) => {
    const guardianUid = requireAuth(request);
    const email = String(request.auth?.token.email ?? "").trim().toLowerCase();
    const rawCode = request.data?.inviteCode;
    if (typeof rawCode !== "string" || rawCode.length < 20 || !email) {
        throw new https_1.HttpsError("invalid-argument", "A valid invitation and verified email are required.");
    }
    const codeHash = (0, node_crypto_1.createHash)("sha256").update(rawCode).digest("hex");
    const inviteRef = db.doc(`guardianInvites/${codeHash}`);
    await db.runTransaction(async (transaction) => {
        const invite = await transaction.get(inviteRef);
        if (!invite.exists) {
            throw new https_1.HttpsError("not-found", "The invitation is invalid or already used.");
        }
        const details = invite.data();
        if (details.expiresAt.toMillis() < Date.now()) {
            throw new https_1.HttpsError("deadline-exceeded", "The invitation has expired.");
        }
        if (details.email !== email) {
            throw new https_1.HttpsError("permission-denied", "Sign in with the email the teacher invited.");
        }
        const student = await transaction.get(studentRef(details.teacherUid, details.studentId));
        const guardianProfile = await transaction.get(db.doc(`users/${guardianUid}`));
        const existingRole = guardianProfile.data()?.role;
        if (existingRole && existingRole !== "guardian") {
            throw new https_1.HttpsError("failed-precondition", "Use a separate account for the family portal.");
        }
        const existingTeacherUid = guardianProfile.data()?.linkedTeacherUid;
        if (existingTeacherUid && existingTeacherUid !== details.teacherUid) {
            throw new https_1.HttpsError("failed-precondition", "This family account is already linked to another workspace.");
        }
        if (!student.exists) {
            throw new https_1.HttpsError("not-found", "The invited student record no longer exists.");
        }
        transaction.update(student.ref, { guardianUid });
        transaction.set(db.doc(`users/${guardianUid}`), {
            role: "guardian",
            linkedTeacherUid: details.teacherUid,
            linkedStudentId: details.studentId,
            email,
            name: String(request.auth?.token.name ?? ""),
            updatedAt: firestore_1.FieldValue.serverTimestamp(),
        }, { merge: true });
        transaction.delete(inviteRef);
    });
    return { linked: true };
});
exports.removeWorkspaceTeacher = (0, https_1.onCall)(async (request) => {
    const ownerUid = requireAuth(request);
    const owner = await db.doc(`users/${ownerUid}`).get();
    if (owner.data()?.role !== "owner" || owner.data()?.workspaceId !== ownerUid) {
        throw new https_1.HttpsError("permission-denied", "Only the workspace owner can remove teachers.");
    }
    const teacherUid = request.data?.teacherUid;
    if (typeof teacherUid !== "string" || !teacherUid || teacherUid === ownerUid) {
        throw new https_1.HttpsError("invalid-argument", "A valid teacher account is required.");
    }
    const membershipRef = db.doc(`users/${ownerUid}/members/${teacherUid}`);
    const teacherRef = db.doc(`users/${teacherUid}`);
    await db.runTransaction(async (transaction) => {
        const membership = await transaction.get(membershipRef);
        const teacher = await transaction.get(teacherRef);
        if (!membership.exists || teacher.data()?.workspaceId !== ownerUid) {
            throw new https_1.HttpsError("not-found", "The teacher is not a member of this workspace.");
        }
        transaction.delete(membershipRef);
        transaction.update(teacherRef, {
            role: "suspended",
            workspaceId: firestore_1.FieldValue.delete(),
            updatedAt: firestore_1.FieldValue.serverTimestamp(),
        });
    });
    return { removed: true };
});
exports.sendManualReminder = (0, https_1.onCall)({ secrets: allSecrets }, async (request) => {
    const requesterUid = requireAuth(request);
    const teacherUid = await workspaceFor(requesterUid);
    const studentId = request.data?.studentId;
    const type = request.data?.type;
    if (typeof studentId !== "string" || !["fee", "absence"].includes(type)) {
        throw new https_1.HttpsError("invalid-argument", "A student ID and valid reminder type are required.");
    }
    const student = await readStudent(teacherUid, studentId);
    const month = monthKey(new Date());
    const id = `manual-${type}-${studentId}-${Date.now()}`;
    const message = type === "fee"
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
exports.sendScheduledFeeReminders = (0, scheduler_1.onSchedule)({
    schedule: "0 8 * * *",
    timeZone: "Asia/Dhaka",
    secrets: allSecrets,
}, async () => {
    const today = new Date();
    const month = monthKey(today);
    const daysInMonth = new Date(today.getFullYear(), today.getMonth() + 1, 0).getDate();
    const currentDay = today.getDate();
    const users = await db.collection("users").where("role", "==", "owner").get();
    for (const teacher of users.docs) {
        const students = await teacher.ref.collection("students").get();
        for (const studentDoc of students.docs) {
            const student = { id: studentDoc.id, ...studentDoc.data() };
            if (student.feePaidMonth === month)
                continue;
            const dueDay = Math.min(Math.max(student.feeDueDay ?? 1, 1), daysInMonth);
            const offset = dueDay - currentDay;
            if (![3, 0, -3].includes(offset))
                continue;
            const key = `fee-${student.id}-${month}-${offset}`;
            const logRef = teacher.ref.collection("reminderLogs").doc(key);
            const existing = await logRef.get();
            if (existing.exists)
                continue;
            const phase = offset === 3 ? "due in 3 days" : offset === 0 ? "due today" : "3 days overdue";
            try {
                await sendAllChannels(student, {
                    subject: "Tuition fee reminder",
                    text: `${student.guardianName || "Guardian"}, the tuition fee of ৳${student.monthlyFee ?? 0} for ${student.name} is ${phase}.`,
                }, logRef);
            }
            catch (error) {
                firebase_functions_1.logger.error("Scheduled fee reminder could not be delivered.", {
                    teacherUid: teacher.id,
                    studentId: student.id,
                    error,
                });
                await logRef.set({
                    studentId: student.id,
                    error: String(error),
                    updatedAt: firestore_1.FieldValue.serverTimestamp(),
                }, { merge: true });
            }
        }
    }
});
exports.notifyOnAbsence = (0, firestore_2.onDocumentWritten)({
    document: "users/{teacherUid}/students/{studentId}",
    secrets: allSecrets,
}, async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after)
        return;
    const previous = before.attendance ?? {};
    const updated = after.attendance ?? {};
    const absentKeys = Object.entries(updated)
        .filter(([key, present]) => present === false && previous[key] !== false)
        .map(([key]) => key);
    for (const key of absentKeys) {
        const id = `absence-${event.params.studentId}-${(0, node_crypto_1.createHash)("sha1").update(key).digest("hex")}`;
        const logRef = db.doc(`users/${event.params.teacherUid}/reminderLogs/${id}`);
        try {
            await sendAllChannels({ ...after, id: event.params.studentId }, {
                subject: "Attendance update",
                text: `${after.name ?? "The student"} was marked absent for the scheduled class. Please contact the teacher if this is unexpected.`,
            }, logRef);
        }
        catch (error) {
            firebase_functions_1.logger.error("Absence notification could not be delivered.", {
                studentId: event.params.studentId,
                error,
            });
        }
    }
});
