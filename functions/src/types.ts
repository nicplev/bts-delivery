/**
 * Type definitions for BTS Delivery App
 */

export interface Delivery {
  id: string;
  schoolId: string;
  schoolName: string;
  date: FirebaseFirestore.Timestamp;
  time?: FirebaseFirestore.Timestamp;
  staffIds: string[];
  staffNames: string[];
  notes?: string;
  createdAt: FirebaseFirestore.Timestamp;
}

export interface Staff {
  id: string;
  name: string;
  uid?: string;
  role: "admin" | "manager" | "staff";
  assignedSchoolIds: string[];
  linkPin?: string;
  calendarToken?: string;
  createdAt: FirebaseFirestore.Timestamp;
}

export interface AppUser {
  uid: string;
  email: string;
  role: "admin" | "manager" | "staff";
  createdAt: FirebaseFirestore.Timestamp;
  lastLoginAt?: FirebaseFirestore.Timestamp;
}

export interface CalendarMetadata {
  staffId: string;
  token: string;
  lastAccessed?: FirebaseFirestore.Timestamp;
  accessCount: number;
  createdAt: FirebaseFirestore.Timestamp;
}
