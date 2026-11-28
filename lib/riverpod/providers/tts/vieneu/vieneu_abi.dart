import 'dart:ffi';

/// Whether the CPU architecture is one the VieNeu libraries are bundled for.
bool get vieneuAbiSupported =>
    Abi.current() == Abi.androidArm64 || Abi.current() == Abi.iosArm64;
