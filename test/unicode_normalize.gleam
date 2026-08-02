// import gleam/string
// import gleeunit/should
// import infra/ffi/unicode

// pub fn match_test() {
//   should.equal(
//     unicode.normalize_nfkd("🄰🄻🅈🄰 🄺🄾🄽🄾🄽🄾🅅🄰") |> string.lowercase,
//     "alya kononova",
//   )
//   should.equal(
//     unicode.normalize_nfkd("Ⓛⓨⓤⓑⓞⓥ 𝐵𝐸𝐿𝑌𝐴𝐸𝑉𝐴") |> string.lowercase,
//     "lyubov belyaeva",
//   )
//   should.equal(
//     unicode.normalize_nfkd("𝔏𝔦𝔫𝔞 ⒼⓊⓈⒺⓋⒶ") |> string.lowercase,
//     "lina guseva",
//   )
//   should.equal(
//     unicode.normalize_nfkd("usual guy") |> string.lowercase,
//     "usual guy",
//   )

//   should.equal(unicode.normalize_nfkd("Rom") |> string.lowercase, "rom")
//   should.equal(unicode.normalize_nfkd("水") |> string.lowercase, "水")
//   should.equal(unicode.normalize_nfkd("🤎") |> string.lowercase, "🤎")

//   should.equal(
//     unicode.normalize_nfkd("𝔖𝔱𝔞𝔰𝔶𝔞 ⒺⓇⓂ️ⒶⓀⓄⓋⒶ") |> string.lowercase,
//     "stasya ermakova",
//   )
// }
