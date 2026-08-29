import gleam/option
import gleam/string
import gleeunit/should
import infra/ffi/unicode
import infra/strict

pub fn unicode_normalize_test() {
  should.equal(
    unicode.normalize_nfkd("🄰🄻🅈🄰 🄺🄾🄽🄾🄽🄾🅅🄰") |> string.lowercase,
    "alya kononova",
  )
  should.equal(
    unicode.normalize_nfkd("Ⓛⓨⓤⓑⓞⓥ 𝐵𝐸𝐿𝑌𝐴𝐸𝑉𝐴") |> string.lowercase,
    "lyubov belyaeva",
  )
  should.equal(
    unicode.normalize_nfkd("𝔏𝔦𝔫𝔞 ⒼⓊⓈⒺⓋⒶ") |> string.lowercase,
    "lina guseva",
  )
  should.equal(
    unicode.normalize_nfkd("usual guy") |> string.lowercase,
    "usual guy",
  )

  should.equal(unicode.normalize_nfkd("Rom") |> string.lowercase, "rom")
  should.equal(unicode.normalize_nfkd("水") |> string.lowercase, "水")
  should.equal(unicode.normalize_nfkd("🤎") |> string.lowercase, "🤎")

  should.equal(
    unicode.normalize_nfkd("𝔖𝔱𝔞𝔰𝔶𝔞 ⒺⓇⓂ️ⒶⓀⓄⓋⒶ") |> string.lowercase,
    "stasya ermakova",
  )
}

pub fn has_hidden_numbers_test() {
  should.be_false(strict.has_hidden_numbers(option.Some("200")))
  should.be_false(strict.has_hidden_numbers(option.Some("200+")))
  should.be_false(strict.has_hidden_numbers(option.Some("2к")))
  should.be_false(strict.has_hidden_numbers(option.Some("привет")))
  should.be_false(strict.has_hidden_numbers(option.Some("2rue")))
  should.be_false(strict.has_hidden_numbers(option.Some("2 okay")))
  should.be_false(strict.has_hidden_numbers(option.Some("2oz")))
  should.be_false(strict.has_hidden_numbers(option.Some("2ой закон ньютона")))

  should.be_true(strict.has_hidden_numbers(option.Some("2ой работа 5oOруб")))
  should.be_true(strict.has_hidden_numbers(option.Some("2oo")))
  should.be_true(strict.has_hidden_numbers(option.Some("2oo+")))
  should.be_true(strict.has_hidden_numbers(option.Some("2ООк")))
  should.be_true(strict.has_hidden_numbers(option.Some("2ОО к")))
  should.be_true(strict.has_hidden_numbers(option.Some("2OO")))
  should.be_true(strict.has_hidden_numbers(option.Some("20oo")))
  should.be_true(strict.has_hidden_numbers(option.Some("2 0oo")))
}
