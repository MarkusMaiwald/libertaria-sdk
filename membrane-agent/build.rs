fn main() {
    // Link against Zig QVL FFI shared library
    let sdk_root = std::env::var("CARGO_MANIFEST_DIR")
        .expect("CARGO_MANIFEST_DIR not set");
    let lib_path = format!("{}/../zig-out/lib", sdk_root);
    
    println!("cargo:rustc-link-search=native={}", lib_path);
    println!("cargo:rustc-link-lib=static=qvl_ffi");
    println!("cargo:rerun-if-changed=../zig-out/lib/libqvl_ffi.a");
    println!("cargo:rerun-if-changed=../l1-identity/qvl.h");
}
