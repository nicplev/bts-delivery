import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import {generateCalendarFeed} from "./calendar-feed";
import {onDeliveryChange} from "./delivery-trigger";
import {autoStopExpiredTimers} from "./timer-auto-stop";

// Initialize Firebase Admin
admin.initializeApp();

// Export HTTP function for calendar feed
export const calendar = functions.https.onRequest(generateCalendarFeed);

// Export Firestore trigger for delivery changes
export const onDeliveryChanged = onDeliveryChange;

// Export scheduled function for auto-stopping expired timers (5 hour limit)
export const timerAutoStop = autoStopExpiredTimers;
