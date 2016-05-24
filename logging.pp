--- a/osnailyfacter/manifests/logging/logging.pp        2015-07-13 15:31:04.161389388 +0000
+++ b/osnailyfacter/manifests/logging/logging.pp        2015-07-13 15:31:12.573398916 +0000
@@ -53,7 +53,7 @@
     # keep four weekly log rotations,
     # force rotate if 300M size have exceeded
     rotation           => 'weekly',
-    keep               => '4',
+    keep               => '1000',
     minsize            => '10M',
     maxsize            => '100M',
     # remote servers to send logs to
