import features/check_chat_clones.{smart_compare}
import gleam/list
import gleeunit
import gleeunit/should
import infra/helpers
import infra/log

pub fn main() {
  gleeunit.main()
}

pub fn female_name_test() {
  let names = ["dina", "daria", "daisy", "veronika", "аня"]
  should.be_true(helpers.has_woman_name(names, "daisy"))
  should.be_true(helpers.has_woman_name(names, "😊dina😊"))
  should.be_true(helpers.has_woman_name(names, "Ⓥⓔⓡⓞⓝⓘⓚⓐ"))
  should.be_true(helpers.has_woman_name(names, "daisy)"))
  should.be_true(helpers.has_woman_name(names, "daria surname"))
  should.be_true(helpers.has_woman_name(names, "surname daria"))
  should.be_true(helpers.has_woman_name(names, "dina<3"))
  should.be_true(helpers.has_woman_name(names, "Аня"))
  should.be_false(helpers.has_woman_name(names, "dfgh"))
  should.be_false(helpers.has_woman_name(names, "Alex"))
  should.be_false(helpers.has_woman_name(names, "Rom"))
  should.be_false(helpers.has_woman_name(names, "J$ Veron"))
  should.be_false(helpers.has_woman_name(names, "Ya2ba"))
  should.be_false(helpers.has_woman_name(names, "some user"))
  should.be_false(helpers.has_woman_name(names, "soMeAnotherU$er<3"))
}

pub fn smart_compare_test() {
  [
    #("apple", "banana"),
    #("Грязин Лаундж Зон", "Gryazin"),
    #("Gagarin Crypto Chat", "Gagarin Crypto"),
    #("Gagarin Crypto Chat", "alpaca"),
    #("Gagarin Crypto Chat", "Chat Gagarin Crypt0"),
  ]
  |> list.each(fn(el) {
    let result = smart_compare(el.0, el.1)
    case result {
      False -> should.be_false(result)
      True -> {
        log.printf("FAIL: Strings `{0}` and `{1} should be not equal`", [
          el.0,
          el.1,
        ])
        should.be_false(result)
      }
    }
  })

  [
    #("альпака чат", "альпака чат"),
    #("boss", "8o55"),
    #("HELLO", "helloo"),
    #(" hello ", "hello"),
    #("Грязин Лаундж Зон", "Грязин Лаундж З0н"),
    #("Грязин Лаундж Зон", " Гря3ин  Лаундж  Зон"),
    #("Gagarin Crypto Chat", "Gagarin Crypto Chat"),
    #("Gagarin Crypto Chat", "Gag4r1n Crypt0 Ch4t"),
    #("Gagarin Crypto Chat", " Gag4r1n Crypt0 Ch4t "),
  ]
  |> list.each(fn(el) {
    let result = smart_compare(el.0, el.1)
    case result {
      False -> {
        log.printf("FAIL: Strings `{0}` and `{1} should be equal`", [
          el.0,
          el.1,
        ])
        should.be_true(result)
      }
      True -> {
        should.be_true(result)
      }
    }
  })
}
