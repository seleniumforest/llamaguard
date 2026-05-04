import gleam/dynamic/decode
import gleam/json

pub type Cached(a) {
  Cached(updated_at: Int, value: a)
}

pub fn cacheify(obj: Cached(a), encoder: fn(a) -> json.Json) -> json.Json {
  json.object([
    #("updated_at", json.int(obj.updated_at)),
    #("value", encoder(obj.value)),
  ])
}

pub fn decacheify(
  name: String,
  decoder: decode.Decoder(a),
  next: fn(Cached(a)) -> decode.Decoder(b),
) {
  use updated_at <- decode.subfield([name, "updated_at"], decode.int)
  use value <- decode.subfield([name, "value"], decoder)

  next(Cached(updated_at:, value:))
}
