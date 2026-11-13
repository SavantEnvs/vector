#![no_main]
use dnsmsg_parser::dns_message_parser::DnsMessageParser;
use libfuzzer_sys::fuzz_target;

// Vector's DNS wire-format parser (dnstap source). A fresh parser per call keeps each result
// dependent only on the input.
fuzz_target!(|data: &[u8]| {
    let _ = DnsMessageParser::new(data.to_vec()).parse_as_query_message();
    let _ = DnsMessageParser::new(data.to_vec()).parse_as_update_message();
});
