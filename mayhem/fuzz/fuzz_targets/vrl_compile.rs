#![no_main]
use libfuzzer_sys::fuzz_target;

// The VRL compiler with the same standard library Vector's remap transform registers.
fuzz_target!(|data: &str| {
    let fns = vrl::stdlib::all();
    let _ = vrl::compiler::compile(data, &fns);
});
