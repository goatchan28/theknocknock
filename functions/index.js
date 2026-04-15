const {onDocumentCreated} = require('firebase-functions/v2/firestore');
const {onSchedule} = require('firebase-functions/v2/scheduler');
const {logger} = require('firebase-functions');
const {defineSecret} = require('firebase-functions/params');
const {initializeApp} = require('firebase-admin/app');
const {getMessaging} = require('firebase-admin/messaging');
const {getFirestore, FieldValue} = require('firebase-admin/firestore');

initializeApp();

const db = getFirestore();
const RESEND_API_KEY = defineSecret('RESEND_API_KEY');
const REPORT_ALERT_TO_EMAIL = 'manaschan8@gmail.com';
const REPORT_ALERT_FROM_EMAIL = 'Knocknock Reports <onboarding@resend.dev>';

exports.sendPushForNotification = onDocumentCreated(
  {
    document: 'notifications/{notificationId}',
    serviceAccount: 'theknocknock-f558c@appspot.gserviceaccount.com',
  },
  async (event) => {
    logger.info('sendPushForNotification invoked', {
      notificationId: event.params.notificationId,
    });

    const snap = event.data;
    if (!snap) {
      logger.info('No snapshot data, skipping');
      return;
    }

    const data = snap.data() || {};
    const recipientId = (data.recipientId || '').trim();
    const notificationType = String(data.type || '');
    if (!recipientId) {
      logger.info('Missing recipientId, skipping');
      return;
    }

    const userSnap = await db.collection('users').doc(recipientId).get();
    if (!userSnap.exists) {
      logger.info('Recipient user doc missing, skipping', {recipientId});
      return;
    }

    const userData = userSnap.data() || {};
    const notificationsEnabled =
      userData?.onboarding?.notificationsEnabled === true;
    if (!notificationsEnabled) {
      logger.info('Notifications disabled for recipient, skipping', {recipientId});
      return;
    }
    const tokens = Array.isArray(userData.notificationTokens)
      ? userData.notificationTokens.filter(
          (token) => typeof token === 'string' && token.trim().length > 0,
        )
      : [];

    if (!tokens.length) {
      logger.info('No notification tokens on user doc, skipping', {recipientId});
      return;
    }

    const unreadSnapshot = await db
      .collection('notifications')
      .where('recipientId', '==', recipientId)
      .where('readAt', '==', null)
      .limit(200)
      .get();
    const unreadCount = unreadSnapshot.size;

    const payload = {
      notification: {
        title: typeof data.title === 'string' ? data.title : 'Knocknock',
        body: typeof data.body === 'string' ? data.body : '',
      },
      data: {
        type: String(data.type || ''),
        listingId: String(data.listingId || ''),
        offerId: String(data.offerId || ''),
      },
      apns: {
        payload: {
          aps: {
            badge: unreadCount,
            sound: 'default',
          },
        },
      },
      android: {
        notification: {
          notificationCount: unreadCount,
        },
      },
      tokens,
    };

    let response;
    try {
      response = await getMessaging().sendEachForMulticast(payload);
    } catch (error) {
      logger.error('FCM send failed', {
        recipientId,
        error: error?.message || String(error),
      });
      return;
    }

    logger.info('FCM send attempted', {
      recipientId,
      notificationType,
      tokenCount: tokens.length,
      unreadCount,
      successCount: response.successCount,
      failureCount: response.failureCount,
    });

    if (!response.failureCount) {
      return;
    }

    const invalidTokens = [];
    for (let i = 0; i < response.responses.length; i += 1) {
      const result = response.responses[i];
      if (result.success) {
        continue;
      }
      const code = result.error?.code || '';
      if (
        code === 'messaging/invalid-registration-token' ||
        code === 'messaging/registration-token-not-registered'
      ) {
        invalidTokens.push(tokens[i]);
      }
    }

    if (invalidTokens.length) {
      await db
        .collection('users')
        .doc(recipientId)
        .update({
          notificationTokens: FieldValue.arrayRemove(...invalidTokens),
        });
      logger.info('Removed invalid tokens', {
        recipientId,
        removedCount: invalidTokens.length,
      });
    }
  },
);

exports.emailAdminOnReport = onDocumentCreated(
  {
    document: 'reports/{reportId}',
    serviceAccount: 'theknocknock-f558c@appspot.gserviceaccount.com',
    secrets: [RESEND_API_KEY],
  },
  async (event) => {
    const snap = event.data;
    if (!snap) {
      return;
    }

    const reportId = event.params.reportId;
    const data = snap.data() || {};
    const reporterId = String(data.reporterId || '').trim();
    const reason = String(data.reason || '').trim();
    const reportTypeRaw = String(data.reportType || '').trim().toLowerCase();
    const reportType = reportTypeRaw === 'report_user' ? 'report_user' : 'report_listing';
    const listingId = String(data.listingId || '').trim();
    const reportedUserId = String(data.reportedUserId || '').trim();
    const targetId = String(data.targetId || '').trim();
    let listingTitle = String(data.listingTitle || '').trim();

    const resendApiKey = RESEND_API_KEY.value();
    if (!resendApiKey) {
      logger.warn('Report email skipped: RESEND_API_KEY secret missing', {reportId});
      return;
    }

    let reporterName = reporterId;
    if (reporterId.length > 0) {
      try {
        const reporterSnap = await db.collection('public_profiles').doc(reporterId).get();
        const displayName = String(reporterSnap.data()?.displayName || '').trim();
        if (displayName.length > 0) {
          reporterName = displayName;
        }
      } catch (_) {
        // best-effort enrichment
      }
    }

    let resolvedReportedUserId = reportedUserId;
    let reportedUserName = String(data.reportedDisplayName || '').trim();

    if (reportType === 'report_listing' && listingId.length > 0) {
      try {
        const listingSnap = await db.collection('listings').doc(listingId).get();
        if (listingSnap.exists) {
          const listingData = listingSnap.data() || {};
          const listingOwnerId = String(listingData.ownerId || '').trim();
          const listingOwnerName = String(listingData.ownerDisplayName || '').trim();
          const listingTitleFromDoc = String(listingData.title || '').trim();
          if (listingTitle.length === 0 && listingTitleFromDoc.length > 0) {
            listingTitle = listingTitleFromDoc;
          }
          if (resolvedReportedUserId.length === 0 && listingOwnerId.length > 0) {
            resolvedReportedUserId = listingOwnerId;
          }
          if (reportedUserName.length === 0 && listingOwnerName.length > 0) {
            reportedUserName = listingOwnerName;
          }
        }
      } catch (_) {
        // best-effort enrichment
      }
    }

    if (resolvedReportedUserId.length > 0 && reportedUserName.length === 0) {
      try {
        const reportedProfileSnap = await db
          .collection('public_profiles')
          .doc(resolvedReportedUserId)
          .get();
        const displayName = String(reportedProfileSnap.data()?.displayName || '').trim();
        if (displayName.length > 0) {
          reportedUserName = displayName;
        }
      } catch (_) {
        // best-effort enrichment
      }
    }

    const reportLabel = reportType === 'report_user' ? 'report_user' : 'report_listing';
    const targetLabel = reportType === 'report_user' ?
      (resolvedReportedUserId || targetId || '(unknown user)') :
      (listingId || targetId || '(unknown listing)');
    const consoleUrl = `https://console.firebase.google.com/project/theknocknock-f558c/firestore/data/~2Freports~2F${reportId}`;
    const subject = `[Knocknock] New ${reportLabel}`;

    const bodyLines = [
      `A new ${reportLabel} was submitted.`,
      '',
      `reportId: ${reportId}`,
      `reporterId: ${reporterId || '(unknown)'}`,
      `reporterName: ${reporterName || '(unknown)'}`,
      `targetId: ${targetLabel}`,
      `reportedUserId: ${resolvedReportedUserId || '(unknown)'}`,
      `reportedUserName: ${reportedUserName || '(unknown)'}`,
      ...(listingTitle.length > 0 ? [`listingTitle: ${listingTitle}`] : []),
      `reason: ${reason || '(no reason provided)'}`,
      '',
      `Open in Firebase Console: ${consoleUrl}`,
    ];

    try {
      const response = await fetch('https://api.resend.com/emails', {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${resendApiKey}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          from: REPORT_ALERT_FROM_EMAIL,
          to: [REPORT_ALERT_TO_EMAIL],
          subject,
          text: bodyLines.join('\n'),
        }),
      });

      if (!response.ok) {
        const errorBody = await response.text();
        logger.error('Report email send failed', {
          reportId,
          status: response.status,
          errorBody,
        });
        return;
      }

      logger.info('Report alert email sent', {
        reportId,
        reportType,
        targetId: targetLabel,
      });
    } catch (error) {
      logger.error('Report email exception', {
        reportId,
        error: error?.message || String(error),
      });
    }
  },
);

exports.sendUrgentBorrowAlerts = onDocumentCreated(
  {
    document: 'listings/{listingId}',
    serviceAccount: 'theknocknock-f558c@appspot.gserviceaccount.com',
  },
  async (event) => {
    const snap = event.data;
    if (!snap) {
      return;
    }

    const listingId = event.params.listingId;
    const listing = snap.data() || {};
    const ownerId = String(listing.ownerId || '').trim();
    const listingType = String(listing.type || '').trim();
    const listingStatus = String(listing.status || '').trim();
    const urgentUntilRaw = listing.urgentUntil;
    const urgentUntil = urgentUntilRaw &&
      typeof urgentUntilRaw.toDate === 'function' ?
      urgentUntilRaw.toDate() :
      null;
    const isUrgentActive = urgentUntil instanceof Date &&
      urgentUntil.getTime() > Date.now();

    if (
      ownerId.length === 0 ||
      listingType !== 'borrow' ||
      listingStatus !== 'active' ||
      !isUrgentActive
    ) {
      return;
    }

    const title = String(listing.title || '').trim();
    const category = String(listing.category || '').trim();
    const body = title
      ? `Urgent borrow request: ${title}.`
      : 'A new urgent borrow request was posted.';

    const usersSnapshot = await db
      .collection('users')
      .where('onboarding.urgentAlertsEnabled', '==', true)
      .get();

    if (usersSnapshot.empty) {
      logger.info('No urgent-alert recipients found', {listingId});
      return;
    }

    let batch = db.batch();
    let batchOps = 0;
    let recipientCount = 0;

    for (const userDoc of usersSnapshot.docs) {
      if (userDoc.id === ownerId) {
        continue;
      }

      const userData = userDoc.data() || {};
      const notificationsEnabled =
        userData?.onboarding?.notificationsEnabled === true;
      if (!notificationsEnabled) {
        continue;
      }

      const notificationRef = db.collection('notifications').doc();
      batch.set(notificationRef, {
        recipientId: userDoc.id,
        actorId: ownerId,
        type: 'urgent_borrow_posted',
        title: category
          ? `Urgent borrow in ${category}`
          : 'Urgent borrow alert',
        body,
        listingId,
        offerId: null,
        createdAt: FieldValue.serverTimestamp(),
        readAt: null,
      });
      batchOps += 1;
      recipientCount += 1;

      if (batchOps >= 450) {
        await batch.commit();
        batch = db.batch();
        batchOps = 0;
      }
    }

    if (batchOps > 0) {
      await batch.commit();
    }

    logger.info('Queued urgent borrow notifications', {
      listingId,
      ownerId,
      recipientCount,
    });
  },
);

exports.expireUrgentBorrowTimers = onSchedule(
  {
    schedule: 'every 5 minutes',
    serviceAccount: 'theknocknock-f558c@appspot.gserviceaccount.com',
    timeZone: 'America/New_York',
  },
  async () => {
    const now = new Date();
    const epoch = new Date(0);

    const snapshot = await db
      .collection('listings')
      .where('urgentUntil', '>', epoch)
      .where('urgentUntil', '<=', now)
      .limit(200)
      .get();

    if (snapshot.empty) {
      return;
    }

    let batch = db.batch();
    let batchOps = 0;
    let processed = 0;
    let notified = 0;

    for (const doc of snapshot.docs) {
      const data = doc.data() || {};
      const listingType = String(data.type || '').trim();
      const listingStatus = String(data.status || '').trim();
      const ownerId = String(data.ownerId || '').trim();
      const acceptedOfferId = String(data.acceptedOfferId || '').trim();
      const urgentUntilRaw = data.urgentUntil;
      const urgentUntil =
        urgentUntilRaw && typeof urgentUntilRaw.toDate === 'function' ?
          urgentUntilRaw.toDate() :
          null;

      if (
        listingType !== 'borrow' ||
        listingStatus !== 'active' ||
        ownerId.length === 0 ||
        acceptedOfferId.length > 0 ||
        !(urgentUntil instanceof Date) ||
        urgentUntil.getTime() > now.getTime()
      ) {
        continue;
      }

      batch.update(doc.ref, {
        urgent: true,
        urgentUntil: FieldValue.delete(),
        urgentExpiredAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      batchOps += 1;
      processed += 1;

      const offerResponseSnapshot = await db
        .collection('offers')
        .where('listingId', '==', doc.id)
        .limit(1)
        .get();

      const listingTitle = String(data.title || '').trim();
      const notificationRef = db.collection('notifications').doc();
      batch.set(notificationRef, {
        recipientId: ownerId,
        actorId: 'system',
        type: 'urgent_no_response',
        title: offerResponseSnapshot.empty ? 'No responses yet' : 'Urgent timer ended',
        body: offerResponseSnapshot.empty
          ? (
            listingTitle.length > 0 ?
              `No one responded to your urgent request for ${listingTitle}. Would you like to reset the timer?` :
              'No one responded to your urgent request. Would you like to reset the timer?'
          )
          : (
            listingTitle.length > 0 ?
              `Urgent timer ended for ${listingTitle}. Check requests or reset the timer if needed.` :
              'Your urgent timer ended. Check requests or reset the timer if needed.'
          ),
        listingId: doc.id,
        offerId: null,
        createdAt: FieldValue.serverTimestamp(),
        readAt: null,
      });
      batchOps += 1;
      notified += 1;

      if (batchOps >= 450) {
        await batch.commit();
        batch = db.batch();
        batchOps = 0;
      }
    }

    if (batchOps > 0) {
      await batch.commit();
    }

    logger.info('Processed expired urgent borrow timers', {
      inspectedCount: snapshot.size,
      processedCount: processed,
      notifiedCount: notified,
    });
  },
);

exports.sendReturnDueSoonNudges = onSchedule(
  {
    schedule: 'every 30 minutes',
    serviceAccount: 'theknocknock-f558c@appspot.gserviceaccount.com',
    timeZone: 'America/New_York',
  },
  async () => {
    const now = new Date();
    const in24h = new Date(now.getTime() + 24 * 60 * 60 * 1000);

    const offersSnapshot = await db
      .collection('offers')
      .where('returnDueAt', '>', now)
      .where('returnDueAt', '<=', in24h)
      .limit(300)
      .get();

    if (offersSnapshot.empty) {
      return;
    }

    let batch = db.batch();
    let batchOps = 0;
    let notifiedOffers = 0;

    for (const offerDoc of offersSnapshot.docs) {
      const data = offerDoc.data() || {};
      const status = String(data.status || '').trim();
      if (status !== 'accepted') {
        continue;
      }
      if (data.pickedUpAt == null) {
        continue;
      }
      if (data.returnedAt != null) {
        continue;
      }
      if (data.dueSoonNudgedAt != null) {
        continue;
      }

      const listingId = String(data.listingId || '').trim();
      const ownerId = String(data.ownerId || '').trim();
      const requesterId = String(data.requesterId || '').trim();
      if (listingId.length === 0 || ownerId.length === 0 || requesterId.length === 0) {
        continue;
      }

      let listingType = String(data.listingType || '').trim();
      let listingTitle = String(data.listingTitle || '').trim();
      if (listingType.length === 0 || listingTitle.length === 0) {
        const listingSnap = await db.collection('listings').doc(listingId).get();
        if (listingSnap.exists) {
          const listingData = listingSnap.data() || {};
          if (listingType.length === 0) {
            listingType = String(listingData.type || '').trim();
          }
          if (listingTitle.length === 0) {
            listingTitle = String(listingData.title || '').trim();
          }
        }
      }

      const normalizedType = listingType === 'borrow' ? 'borrow' : 'lend';
      const lenderId = normalizedType === 'borrow' ? requesterId : ownerId;
      const borrowerId = normalizedType === 'borrow' ? ownerId : requesterId;
      if (lenderId.length === 0 || borrowerId.length === 0 || lenderId === borrowerId) {
        continue;
      }

      const itemLabel = listingTitle.length > 0 ? listingTitle : 'this item';
      const lenderNotificationRef = db.collection('notifications').doc();
      batch.set(lenderNotificationRef, {
        recipientId: lenderId,
        actorId: 'system',
        type: 'return_due_soon_lender',
        title: 'Return due in 1 day',
        body: `1 day left before ${itemLabel} is due. Please remind the borrower.`,
        listingId,
        offerId: offerDoc.id,
        createdAt: FieldValue.serverTimestamp(),
        readAt: null,
      });
      batchOps += 1;

      const borrowerNotificationRef = db.collection('notifications').doc();
      batch.set(borrowerNotificationRef, {
        recipientId: borrowerId,
        actorId: 'system',
        type: 'return_due_soon_borrower',
        title: 'Return reminder',
        body: `You have 1 day left to return ${itemLabel}.`,
        listingId,
        offerId: offerDoc.id,
        createdAt: FieldValue.serverTimestamp(),
        readAt: null,
      });
      batchOps += 1;

      batch.update(offerDoc.ref, {
        dueSoonNudgedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      batchOps += 1;
      notifiedOffers += 1;

      if (batchOps >= 450) {
        await batch.commit();
        batch = db.batch();
        batchOps = 0;
      }
    }

    if (batchOps > 0) {
      await batch.commit();
    }

    logger.info('Processed return-due-soon nudges', {
      inspectedCount: offersSnapshot.size,
      notifiedOffers,
    });
  },
);
