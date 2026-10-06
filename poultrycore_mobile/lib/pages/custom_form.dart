import 'package:flutter/widgets.dart';

import '../models/company.dart';
import '../state/session.dart';

/// A page whose web dialog has logic a declarative [FormDef] cannot express
/// — fields that appear on a switch, a batch that prefills the date and
/// breed, permission toggles — gets a screen of its own, built by one of
/// these. `existing` is null for Add and the record for Edit.
typedef CustomFormBuilder = Widget Function(
    Session session, Company company, Map<String, dynamic>? existing);

/// A web route that is a screen of its own rather than a list — a settings
/// page such as Egg Pick Times. Nav links to the route open it directly.
typedef PageScreenBuilder = Widget Function(Session session, Company company);
