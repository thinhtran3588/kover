import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

/// Bundles the prebuilt sea-g2p library of the target, see scripts/build.sh.
void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    final code = input.config.code;
    final folder = switch ((code.targetOS, code.targetArchitecture)) {
      (OS.android, Architecture.arm64) => 'android-arm64',
      (OS.android, Architecture.x64) => 'android-x64',
      (OS.iOS, Architecture.arm64) =>
        code.iOS.targetSdk == IOSSdk.iPhoneSimulator
            ? 'ios-sim-arm64'
            : 'ios-arm64',
      // The library is only used on the platforms above.
      _ => null,
    };
    if (folder == null) return;

    final name = code.targetOS == OS.android
        ? 'libsea_g2p_rs.so'
        : 'libsea_g2p_rs.dylib';
    final file = input.packageRoot.resolve('prebuilt/$folder/$name');
    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: 'sea_g2p.dart',
        linkMode: DynamicLoadingBundled(),
        file: file,
      ),
    );
    output.dependencies.add(file);
  });
}
