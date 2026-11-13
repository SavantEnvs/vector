#![no_main]
use libfuzzer_sys::fuzz_target;

// Non-UTF-8 input is rejected by libfuzzer-sys (the harness returns -1 for it).
fuzz_target!(|data: &str| {
    let _ = vrl::parser::parse(data);
});
