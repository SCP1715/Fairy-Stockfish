# Regression: a small node budget must still finish one complete iteration.
set timeout 30
set engineBinary "./stockfish"
if {[info exists env(LIFECHESS_ENGINE_BIN)]} { set engineBinary $env(LIFECHESS_ENGINE_BIN) }
spawn $engineBinary
send "uci\n"
expect "uciok" {} timeout { exit 1 }
send "setoption name UCI_Variant value lifechess\n"
send "isready\n"
expect "readyok" {} timeout { exit 1 }
log_user 0

send "position startpos\ngo nodes 2000\n"
expect -re {info depth 1 .*score (cp|mate) -?[0-9]+} {} timeout {
  puts stderr "A 2000-node search stopped before completing depth 1"
  exit 1
}
expect -re {bestmove [a-h][1-8][a-h][1-8]} {} timeout {
  puts stderr "A 2000-node search did not return its completed-iteration move"
  exit 1
}

send "quit\n"
expect eof
wait
log_user 1
puts "LifeChess node-budget tests passed"
