import gleeunit
import gleeunit/should
import infra/helpers.{match_ids}

pub fn main() {
  gleeunit.main()
}

pub fn match_test() {
  should.be_true(match_ids("123@qwe", "123"))
  should.be_true(match_ids("123", "123"))
  should.be_true(match_ids("@qwe", "@qwe"))
  should.be_true(match_ids("123", "123@qwe"))
  should.be_true(match_ids("123@qwe", "123@qwe"))
  should.be_false(match_ids("123", "@qwe"))
  should.be_false(match_ids("123", "1234"))
  should.be_false(match_ids("@qwe", "@qwer"))
  should.be_false(match_ids("@qwe", "123"))
  should.be_false(match_ids("123@qwe", "1234@qwer"))
}
