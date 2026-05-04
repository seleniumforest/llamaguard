import gleam/dynamic/decode

pub fn int_field(
  name: String,
  next: fn(Int) -> decode.Decoder(a),
) -> decode.Decoder(a) {
  use val <- decode.optional_field(name, 0, decode.int)
  next(val)
}

pub fn bool_field(
  name: String,
  next: fn(Bool) -> decode.Decoder(a),
) -> decode.Decoder(a) {
  use val <- decode.optional_field(name, False, decode.bool)
  next(val)
}

pub fn string_list_field(
  name: String,
  next: fn(List(String)) -> decode.Decoder(a),
) -> decode.Decoder(a) {
  use val <- decode.optional_field(name, [], decode.list(decode.string))
  next(val)
}

pub fn int_list_field(
  name: String,
  next: fn(List(Int)) -> decode.Decoder(a),
) -> decode.Decoder(a) {
  use val <- decode.optional_field(name, [], decode.list(decode.int))
  next(val)
}
