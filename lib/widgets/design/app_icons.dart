import 'package:flutter/widgets.dart';
import 'package:heroicons_flutter/heroicons_flutter.dart';

/// The Heroicons the app uses, by meaning, so screens stay consistent.
///
/// Outline is the default; `*Solid` variants are for selected tabs and status,
/// `*Mini` (20 pt Heroicons) for small inline metadata. Screens use these names
/// only; add a semantic name here when a new glyph is needed.
abstract final class AppIcons {
  // Tabs.
  static const IconData deliveries = HeroiconsOutline.truck;
  static const IconData deliveriesSolid = HeroiconsSolid.truck;
  static const IconData schools = HeroiconsOutline.academicCap;
  static const IconData schoolsSolid = HeroiconsSolid.academicCap;
  static const IconData profile = HeroiconsOutline.user;
  static const IconData profileSolid = HeroiconsSolid.user;

  // Navigation.
  static const IconData back = HeroiconsOutline.chevronLeft;
  static const IconData more = HeroiconsOutline.ellipsisHorizontal;
  static const IconData chevron = HeroiconsMini.chevronRight;
  static const IconData chevronDown = HeroiconsMini.chevronDown;
  static const IconData chevronUp = HeroiconsMini.chevronUp;
  static const IconData previousPage = HeroiconsOutline.chevronLeft;
  static const IconData nextPage = HeroiconsOutline.chevronRight;
  static const IconData close = HeroiconsOutline.xMark;
  static const IconData search = HeroiconsOutline.magnifyingGlass;
  static const IconData filter = HeroiconsOutline.funnel;
  static const IconData settings = HeroiconsOutline.cog6Tooth;
  static const IconData external = HeroiconsOutline.arrowTopRightOnSquare;
  static const IconData dragHandle = HeroiconsOutline.bars3;
  static const IconData enlarge = HeroiconsOutline.arrowsPointingOut;
  static const IconData shrink = HeroiconsOutline.arrowsPointingIn;
  static const IconData resetZoom = HeroiconsOutline.magnifyingGlassMinus;

  // Status.
  static const IconData check = HeroiconsOutline.check;
  static const IconData complete = HeroiconsSolid.checkCircle;
  static const IconData completeOutline = HeroiconsOutline.checkCircle;
  static const IconData warning = HeroiconsSolid.exclamationTriangle;
  static const IconData warningOutline = HeroiconsOutline.exclamationTriangle;
  static const IconData error = HeroiconsOutline.exclamationCircle;
  static const IconData info = HeroiconsSolid.informationCircle;
  static const IconData infoOutline = HeroiconsOutline.informationCircle;
  static const IconData offline = HeroiconsOutline.signalSlash;
  static const IconData online = HeroiconsOutline.signal;
  static const IconData savedOnDevice = HeroiconsOutline.devicePhoneMobile;
  static const IconData waitingToUpload = HeroiconsOutline.cloudArrowUp;
  static const IconData savedToServer = HeroiconsSolid.checkCircle;
  static const IconData paused = HeroiconsOutline.pauseCircle;
  static const IconData lock = HeroiconsOutline.lockClosed;
  static const IconData onlineOnly = HeroiconsOutline.cloud;
  static const IconData history = HeroiconsOutline.clock;
  static const IconData notAttended = HeroiconsOutline.minusCircle;

  // Visit content.
  static const IconData school = HeroiconsOutline.academicCap;
  static const IconData classroom = HeroiconsOutline.userGroup;
  static const IconData records = HeroiconsOutline.clipboardDocumentList;
  static const IconData checklist = HeroiconsOutline.clipboardDocumentCheck;
  static const IconData consumables = HeroiconsOutline.cube;
  static const IconData packs = HeroiconsOutline.archiveBox;
  static const IconData photos = HeroiconsOutline.camera;
  static const IconData gallery = HeroiconsOutline.photo;
  static const IconData notes = HeroiconsOutline.pencilSquare;
  static const IconData document = HeroiconsOutline.documentText;
  static const IconData timer = HeroiconsOutline.clock;
  static const IconData map = HeroiconsOutline.map;
  static const IconData location = HeroiconsOutline.mapPin;
  static const IconData calendar = HeroiconsOutline.calendarDays;
  static const IconData signature = HeroiconsOutline.pencil;
  static const IconData person = HeroiconsOutline.user;
  static const IconData people = HeroiconsOutline.users;
  static const IconData phone = HeroiconsOutline.phone;
  static const IconData email = HeroiconsOutline.envelope;
  static const IconData logout = HeroiconsOutline.arrowRightStartOnRectangle;
  static const IconData report = HeroiconsOutline.documentChartBar;
  static const IconData views = HeroiconsOutline.eye;

  // Accounts and roles.
  static const IconData admin = HeroiconsOutline.shieldCheck;
  static const IconData manager = HeroiconsOutline.briefcase;
  static const IconData role = HeroiconsOutline.identification;
  static const IconData invitation = HeroiconsOutline.key;
  static const IconData verificationCode = HeroiconsOutline.shieldCheck;
  static const IconData link = HeroiconsOutline.link;
  static const IconData showPassword = HeroiconsOutline.eye;
  static const IconData hidePassword = HeroiconsOutline.eyeSlash;
  static const IconData showAll = HeroiconsOutline.eye;

  // Small inline metadata (20 pt mini glyphs).
  static const IconData timerMini = HeroiconsMini.clock;
  static const IconData vehiclesMini = HeroiconsMini.truck;
  static const IconData palletsMini = HeroiconsMini.cube;
  static const IconData staffMini = HeroiconsMini.users;

  // Actions.
  static const IconData add = HeroiconsOutline.plus;
  static const IconData remove = HeroiconsOutline.minus;
  static const IconData removeCircle = HeroiconsOutline.minusCircle;
  static const IconData clearField = HeroiconsSolid.xCircle;
  static const IconData copy = HeroiconsOutline.documentDuplicate;
  static const IconData paste = HeroiconsOutline.clipboardDocument;
  static const IconData edit = HeroiconsOutline.pencilSquare;
  static const IconData delete = HeroiconsOutline.trash;
  static const IconData download = HeroiconsOutline.arrowDownTray;
  static const IconData upload = HeroiconsOutline.arrowUpTray;
  static const IconData retry = HeroiconsOutline.arrowPath;
  static const IconData share = HeroiconsOutline.share;
  static const IconData exportFile = HeroiconsOutline.arrowUpOnSquare;
  static const IconData importFile = HeroiconsOutline.arrowDownOnSquare;
  static const IconData play = HeroiconsSolid.play;
  static const IconData stop = HeroiconsSolid.stop;
}
