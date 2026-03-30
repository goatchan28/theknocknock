const {onDocumentCreated} = require('firebase-functions/v2/firestore');
const {logger} = require('firebase-functions');
const {initializeApp} = require('firebase-admin/app');
const {getMessaging} = require('firebase-admin/messaging');
const {getFirestore, FieldValue} = require('firebase-admin/firestore');

initializeApp();

const db = getFirestore();

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
