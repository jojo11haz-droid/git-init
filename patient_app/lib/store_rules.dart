import 'package:flutter/foundation.dart';

/// App Store rule 3.1.1: on iPhone and iPad, a digital subscription must be
/// bought with Apple's in-app purchase, and an app may not show prices or
/// buttons and links that lead to buying elsewhere. Between's plans are sold
/// on the website, so the iOS build shows no plan screen, prices or "Go
/// Premium" prompts. Anyone who subscribed on the website still gets their
/// Premium features in the app (allowed by rule 3.1.3(b)). Android and other
/// builds keep the plans screen.
bool get canShowPurchase => kIsWeb || defaultTargetPlatform != TargetPlatform.iOS;
