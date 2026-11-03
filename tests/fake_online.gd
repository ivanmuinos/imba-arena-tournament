class_name FakeOnline
extends OnlineApi
## OnlineApi with the network replaced: records every request and answers from a script. Only `_send` and the clock
## are replaced, so URL building, auth headers, response classification and the unavailable state are the real ones.

## Simulated clock (unix seconds).
var clock := 1000.0
## true: every request fails like an unreachable server.
var down := false
## [{method, url, headers, body}]
var calls: Array = []
var _replies: Array = []  # [{code, body}], consumed in order; default is 200 "null"


func _now() -> float:
	return clock


## The next request gets this HTTP answer.
func queue_reply(code: int, body: String) -> void:
	_replies.append({"code": code, "body": body})


## Convenience: the next request succeeds with this JSON value.
func queue_ok(value: Variant) -> void:
	queue_reply(200, JSON.stringify(value))


func _send(method: int, url: String, headers: Array, body: String, cb: Callable) -> void:
	calls.append({"method": method, "url": url, "headers": headers, "body": body})
	if down:
		cb.call(HTTPRequest.RESULT_CANT_CONNECT, 0, "")
		return
	var reply: Dictionary = _replies.pop_front() if not _replies.is_empty() else {"code": 200, "body": "null"}
	cb.call(HTTPRequest.RESULT_SUCCESS, int(reply.code), str(reply.body))
