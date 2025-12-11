/// Builder entry point for build_runner
library;

import 'package:build/build.dart';
import 'src/supafreeze_builder.dart';
import 'src/supafreeze_post_builder.dart';

/// Creates the supafreeze builder (generates intermediate JSON)
Builder supafreezeBuilder(BuilderOptions options) => SupafreezeBuilder(options);

/// Creates the supafreeze post-process builder (generates model files)
PostProcessBuilder supafreezePostBuilder(BuilderOptions options) =>
    SupafreezePostBuilder();
