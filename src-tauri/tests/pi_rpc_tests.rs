use detdoc_gui::detdoc::pi_rpc::split_jsonl_records;

#[test]
fn jsonl_split_uses_lf_only_and_preserves_unicode_separators_inside_json() {
    let input = b"{\"text\":\"a\xE2\x80\xA8b\"}\n{\"ok\":true}\r\n";
    let records = split_jsonl_records(input).unwrap();
    assert_eq!(records, vec!["{\"text\":\"a\u{2028}b\"}", "{\"ok\":true}"]);
}
