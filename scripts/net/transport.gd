class_name Transport
extends RefCounted
## One network backend behind a tiny interface. GameServer/GameClient only talk to this, so
## ENet (PeerTransport), an in-process link (LoopbackTransport) or GodotSteam's
## SteamMultiplayerPeer (PeerTransport again: it is just another MultiplayerPeer) can be
## swapped without touching the game code.
##
## Peer ids follow Godot's convention: the server is always 1, clients get any other id.

signal peer_connected(id: int)
## Same event, carrying the transport itself (lets GameServer route replies without binding callables:
## a callable bound to the transport that holds it would be a reference cycle).
signal peer_joined(transport: Transport, id: int)
signal peer_disconnected(id: int)
signal message(from: int, msg: Dictionary)
## Client side only.
signal connected_to_server
signal connection_failed

const SERVER_ID := 1


## Pump the backend: emits the signals above. Call every frame.
func poll() -> void:
	pass


## `reliable` = delivered and ordered (lobby, casts, events). Unreliable = latest-wins (snapshots, inputs).
func send(_to: int, _msg: Dictionary, _reliable := true) -> void:
	pass


## Server side: drop a client.
func kick(_id: int) -> void:
	pass


func close() -> void:
	pass


func local_id() -> int:
	return SERVER_ID
