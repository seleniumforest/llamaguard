import gleam/dynamic/decode
import gleam/json
import models/error

pub fn bool_as_int_encoder(val: Bool) {
  json.int(case val {
    False -> 0
    True -> 1
  })
}

pub fn int_to_bool(int: Int) {
  case int {
    0 -> Ok(False)
    1 -> Ok(True)
    _ -> Error(error.GenericError("Cannot decode int as bool"))
  }
}

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
  use val <- decode.optional_field(name, 0, decode.int)
  let assert Ok(bool_val) = int_to_bool(val)
  next(bool_val)
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
