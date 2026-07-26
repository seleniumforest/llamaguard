import gleam/httpc
import gleam/json
import sqlight
import telega/error

pub type BotError {
  GenericError(String)
  TelegaLibError(error.TelegaError)
  CasCheckError(httpc.HttpError)
  CannotFindRealSender

  //storage errors
  InvalidValueError(json.DecodeError)
  DbConnectionError(sqlight.Error)
  DbUpdateError
  DbSaveEmptyResultError
  EmptyDataError
  CacheError
}
