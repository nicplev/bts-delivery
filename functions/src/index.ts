import * as admin from "firebase-admin";
import {generateCalendarFeed} from "./calendar-feed";
import {onDeliveryChange} from "./delivery-trigger";
import {autoStopExpiredTimers} from "./timer-auto-stop";

// Initialize Firebase Admin
admin.initializeApp();

// Export HTTP function for calendar feed
export const calendar = generateCalendarFeed;

// Export Firestore trigger for delivery changes
export const onDeliveryChanged = onDeliveryChange;

// Export scheduled function for auto-stopping expired timers (5 hour limit)
export const timerAutoStop = autoStopExpiredTimers;

export {
  calendarSubscriptionToken,
  issueStaffInvite,
  listStaffDirectory,
  redeemStaffInvite,
} from "./staff-access";

export {prepareVisit} from "./prepare-visit";

export {
  createTeamAccount,
  deleteTeamMember,
  listTeamAccounts,
  setTeamSignIn,
  setTeamSuperAdmin,
} from "./team-admin";
