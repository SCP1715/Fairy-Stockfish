#!/usr/bin/expect

log_user 0
set timeout 20
set engineBinary "./stockfish"
if {[info exists env(LIFECHESS_ENGINE_BIN)]} { set engineBinary $env(LIFECHESS_ENGINE_BIN) }
spawn $engineBinary
send "xboard\nprotover 2\n"
expect -re {feature .*draw=1.*} {} timeout {
  puts stderr "XBoard did not advertise draw-offer support"
  exit 1
}
send "variant lifechess\nforce\nsd 1\n"

# A balanced opening is too early for a voluntary draw offer.
send "setboard rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1 lc1:-\ngo\n"
expect -re {(offer draw|move [a-h][1-8][a-h][1-8])} {} timeout {
  puts stderr "Engine did not respond in the balanced opening"
  exit 1
}
if {[string match "offer draw" $expect_out(0,string)]} {
  puts stderr "Engine offered a draw in the balanced opening"
  exit 1
}

# A winning side rejects an incoming offer even with a claimable 50-move draw.
send "setboard 4k3/8/8/8/8/8/4Q3/4K3 w - - 100 51 lc1:-\ndraw\ngo\n"
expect "move e2e8" {} timeout {
  puts stderr "Winning LifeChess position did not reject the draw offer with a move"
  exit 1
}

# A losing side accepts the opponent's draw offer instead of making a move.
send "force\nsetboard 4k3/8/8/8/8/8/8/3QK3 b - - 0 1 lc1:-\ndraw\ngo\n"
expect "offer draw" {} timeout {
  puts stderr "Losing LifeChess position did not accept the opponent's draw offer"
  exit 1
}

# A severely losing low-material endgame claims an available 50-move draw.
send "force\nsetboard k7/Q7/1K6/8/8/8/8/8 b - - 100 51 lc1:-\ngo\n"
expect -re {1/2-1/2 \{Draw claimed: (repetition|fifty_moves)\}} {} timeout {
  puts stderr "Losing engine did not claim its available 50-move draw"
  exit 1
}

# A deeply losing opening may trigger an offer; it is sent at most once.
send "force\nsetboard rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/QQQQKQQQ b - - 0 1 lc1:-\ngo\n"
expect "offer draw" {} timeout {
  puts stderr "Deeply losing opening did not trigger a draw offer"
  exit 1
}
expect "move " {} timeout {
  puts stderr "Engine did not continue after its agreement offer"
  exit 1
}
send "force\nsetboard rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/QQQQKQQQ b - - 0 1 lc1:-\ngo\n"
expect -re {move [a-h][1-8][a-h][1-8]} {} timeout {
  puts stderr "Engine did not continue after a repeated losing position"
  exit 1
}
set timeout 2
expect -re {offer draw} {
  puts stderr "Engine repeated its draw offer during the same losing stretch"
  exit 1
} timeout {}

send "quit\n"
expect eof
wait
log_user 1
puts "LifeChess draw-policy tests passed"
