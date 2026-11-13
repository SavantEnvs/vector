// Known-answer probe: parses/compiles/runs fixed inputs through the same code the fuzz targets
// exercise and prints the computed values, which mayhem/test.sh asserts exactly.
use std::{env, fs, process::ExitCode};

use dnsmsg_parser::dns_message_parser::DnsMessageParser;
use vrl::compiler::{TargetValue, TimeZone, runtime::Runtime};
use vrl::value::{Secrets, Value};

fn main() -> ExitCode {
    let args: Vec<String> = env::args().collect();
    if args.len() != 3 {
        eprintln!("usage: vector-kat <vrl-parse|vrl-run|dns> <file>");
        return ExitCode::from(2);
    }
    let bytes = match fs::read(&args[2]) {
        Ok(b) => b,
        Err(e) => {
            eprintln!("read {}: {e}", args[2]);
            return ExitCode::from(2);
        }
    };
    match args[1].as_str() {
        "vrl-parse" => {
            let src = String::from_utf8_lossy(&bytes);
            match vrl::parser::parse(src.as_ref()) {
                Ok(program) => println!("parse=ok expressions={}", program.0.len()),
                Err(_) => println!("parse=error"),
            }
        }
        "vrl-run" => {
            let src = String::from_utf8_lossy(&bytes);
            let fns = vrl::stdlib::all();
            let program = match vrl::compiler::compile(src.as_ref(), &fns) {
                Ok(r) => r.program,
                Err(_) => {
                    println!("compile=error");
                    return ExitCode::SUCCESS;
                }
            };
            let mut target = TargetValue {
                value: Value::Object(Default::default()),
                metadata: Value::Object(Default::default()),
                secrets: Secrets::default(),
            };
            let mut runtime = Runtime::default();
            match runtime.resolve(&mut target, &program, &TimeZone::default()) {
                Ok(v) => println!("result={v}"),
                Err(e) => println!("runtime=error {e}"),
            }
        }
        "dns" => {
            match DnsMessageParser::new(bytes.clone()).parse_as_query_message() {
                Ok(m) => {
                    println!("qr={} questions={}", m.header.qr, m.question_section.len());
                    for q in &m.question_section {
                        println!(
                            "question={} type={}",
                            q.name,
                            q.record_type.clone().unwrap_or_default()
                        );
                    }
                    if let Some(opt) = m.opt_pseudo_section {
                        for e in &opt.ede {
                            println!(
                                "ede={} purpose={} extra={}",
                                e.info_code(),
                                e.purpose().unwrap_or("none"),
                                e.extra_text().unwrap_or_else(|| "none".into())
                            );
                        }
                    }
                }
                Err(_) => println!("dns=error"),
            }
        }
        other => {
            eprintln!("unknown mode {other}");
            return ExitCode::from(2);
        }
    }
    ExitCode::SUCCESS
}
