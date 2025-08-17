use std::env;
use std::path::PathBuf;

fn main() {
    // Generate C bindings
    let crate_dir = env::var("CARGO_MANIFEST_DIR").unwrap();
    
    cbindgen::Builder::new()
        .with_crate(crate_dir)
        .with_language(cbindgen::Language::C)
        .with_pragma_once(true)
        .with_include_guard("RUST_SSH_H")
        .generate()
        .expect("Unable to generate bindings")
        .write_to_file("rust_ssh.h");
    
    // Tell cargo to link against system libraries
    if cfg!(target_os = "macos") {
        println!("cargo:rustc-link-lib=framework=Security");
        println!("cargo:rustc-link-lib=framework=CoreFoundation");
    } else if cfg!(target_os = "linux") {
        println!("cargo:rustc-link-lib=ssl");
        println!("cargo:rustc-link-lib=crypto");
    } else if cfg!(target_os = "windows") {
        println!("cargo:rustc-link-lib=ws2_32");
        println!("cargo:rustc-link-lib=user32");
        println!("cargo:rustc-link-lib=crypt32");
    }
}