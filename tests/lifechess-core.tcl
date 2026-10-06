# Run from src/: expect ../tests/lifechess-core.tcl
set timeout 20
set engineBinary "./stockfish"
if {[info exists env(LIFECHESS_ENGINE_BIN)]} { set engineBinary $env(LIFECHESS_ENGINE_BIN) }
spawn $engineBinary
send "uci\n"
expect "uciok" {} timeout { exit 1 }
send "setoption name UCI_Variant value lifechess\n"
send "isready\n"
expect "readyok" {} timeout { exit 1 }
log_user 0

# The exact two-kings condition is an optional claim, never an automatic result.
send "setoption name LifeChess Draw Decisions value true\nposition fen 7k/8/8/8/8/8/8/K7 w - - 0 1 lc1:-\ngo depth 2\n"
expect -re {lifechess-action claim_bare_kings reason bare_kings} {} timeout {
  puts stderr "Bare non-adjacent kings were not returned as a typed draw claim: $expect_out(buffer)"
  catch {send "stop\nquit\n"}
  exit 1
}
expect -re {bestmove [a-h][1-8][a-h][1-8]} {} timeout {
  puts stderr "Search failed to complete after reporting a bare-kings claim"
  exit 1
}

proc perft {fen {expected ""} {depth 1}} {
  send "position fen $fen\ngo perft $depth\n"
  if {$expected eq ""} {
    expect -re {Nodes searched: [0-9]+} {} timeout { exit 1 }
  } else {
    expect -re "Nodes searched: $expected" {} timeout { exit 1 }
  }
  return $expect_out(buffer)
}

# Adjacent kings do not enable this claim; ordinary king capture remains legal.
set adjacentKings [perft "8/8/8/8/8/8/8/Kk6 w - - 0 1"]
if {[string first "a1b1: 1" $adjacentKings] < 0} {
  puts stderr "Adjacent king capture was incorrectly removed"
  exit 1
}

# T01: 16 пешечных, 4 коневых и 5 собственных взятий королём.
perft "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1" 25

# A pawn marked as moved by the editor cannot regain its initial double-step.
set movedHomePawn [perft "4k3/8/8/8/8/8/4P3/4K3 w - - 0 1 lc1:- lm1:0000000000001000"]
if {[string first "e2e4: 1" $movedHomePawn] >= 0 || [string first "e2e3: 1" $movedHomePawn] < 0} {
  puts stderr "A moved pawn on its home rank has incorrect legal moves"
  exit 1
}

# A stale en-passant target without a pawn behind it must not generate a move
# or crash search while looking up the captured square.
set staleEnPassant [perft "4k3/8/8/4P3/8/8/8/4K3 w - d6 0 1 lc1:-"]
if {[string first "e5d6: 1" $staleEnPassant] >= 0} {
  puts stderr "A stale en-passant target generated a capture without a victim"
  exit 1
}
send "position fen 4k3/8/8/4P3/8/8/8/4K3 w - d6 0 1 lc1:-\ngo depth 4\n"
expect -re {bestmove (\S+)} {} timeout {
  puts stderr "Search crashed or timed out on a stale en-passant target"
  exit 1
}

# Vertical castling rights can outlive the enemy king that initially occupies
# the other side's rook square; an empty square is not a color-bearing piece.
set absentVerticalRook [perft "7k/8/8/8/8/8/8/4K3 w V - 0 1 lc1:-"]
if {[string first "e1e3: 1" $absentVerticalRook] >= 0} {
  puts stderr "Vertical castling was generated without its rook"
  exit 1
}
send "position fen 7k/8/8/8/8/8/8/4K3 w V - 0 1 lc1:-\ngo depth 4\n"
expect -re {bestmove (\S+)} {} timeout {
  puts stderr "Search crashed or timed out with a missing vertical rook"
  exit 1
}

# make/unmake regression: perft and search must leave the root position intact.
set restoreFen "r3k2r/1P6/8/8/8/8/8/R3K2R w KQkqVv - 17 9 lc1:-"
send "position fen $restoreFen\nd\n"
expect -re {Fen: ([^\r\n]+)} {} timeout { puts stderr "Could not read pre-perft root FEN"; exit 1 }
set beforePerftFen $expect_out(1,string)
expect -re {Key: ([0-9A-Fa-f]+)} {} timeout { puts stderr "Could not read pre-perft root key"; exit 1 }
set beforePerftKey $expect_out(1,string)
send "go perft 3\n"
expect -re {Nodes searched: [0-9]+} {} timeout { puts stderr "Restore perft timed out"; exit 1 }
send "d\n"
expect -re {Fen: ([^\r\n]+)} {} timeout { puts stderr "Could not read post-perft root FEN"; exit 1 }
if {$beforePerftFen ne $expect_out(1,string)} {
  puts stderr "Perft make/unmake changed the root position"
  exit 1
}
expect -re {Key: ([0-9A-Fa-f]+)} {} timeout { puts stderr "Could not read post-perft root key"; exit 1 }
if {$beforePerftKey ne $expect_out(1,string)} {
  puts stderr "Perft make/unmake changed the root Zobrist key"
  exit 1
}
send "position fen $restoreFen\ngo depth 4\n"
expect -re {bestmove (\S+)} {} timeout { puts stderr "Restore search timed out"; exit 1 }
send "d\n"
expect -re {Fen: ([^\r\n]+)} {} timeout { puts stderr "Could not read post-search root FEN"; exit 1 }
if {$beforePerftFen ne $expect_out(1,string)} {
  puts stderr "Search make/unmake changed the root position"
  exit 1
}
expect -re {Key: ([0-9A-Fa-f]+)} {} timeout { puts stderr "Could not read post-search root key"; exit 1 }
if {$beforePerftKey ne $expect_out(1,string)} {
  puts stderr "Search make/unmake changed the root Zobrist key"
  exit 1
}
send "position startpos\nd\n"
expect "Fen: rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQVkqv - 0 1 lc1:-" {} timeout {
  puts stderr "LifeChess start position lost initial horizontal or future vertical rights"
  exit 1
}

# A black king move consumes only its own vertical right, not White's future right.
send "position startpos moves e2e4 e8e7\nd\n"
expect "Fen: rnbq1bnr/ppppkppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR w KQV - 0 2 lc1:-" {} timeout {
  puts stderr "Vertical castling rights were cleared by the wrong king"
  exit 1
}

# A promoted rook may use the preserved right as soon as it reaches e8.
set output [perft "k7/4P3/8/8/8/8/8/4K3 w V - 0 1"]
if {[string first "e7e8r: 1" $output] < 0} {
  puts stderr "Vertical-right promotion test could not promote a rook on e8"
  exit 1
}
send "position fen k7/4P3/8/8/8/8/8/4K3 w V - 0 1 moves e7e8r\nd\n"
expect "Fen: k3R3/8/8/8/8/8/8/4K3 b V - 0 1 lc1:-" {} timeout {
  puts stderr "Promotion did not preserve the future vertical castling right"
  exit 1
}
set output [perft "k7/4P3/8/8/8/8/8/4K3 w V - 0 1 moves e7e8r a8a7"]
if {[string first "e1e3: 1" $output] < 0} {
  puts stderr "Promoted rook could not exercise the preserved vertical right"
  exit 1
}

# T02: допускаются ходы короля и других фигур под геометрическую атаку.
set output [perft "k3r3/8/8/8/8/8/8/1N2K3 w - - 0 1" 8]
if {[string first "b1c3: 1" $output] < 0 || [string first "e1e2: 1" $output] < 0} {
  puts stderr "T02 failed: moves into attack were not generated"
  exit 1
}

# T03: отсутствие пата — у чёрных пять ходов, каждый из которых допускает взятие.
set t03 "4k3/4B3/4K3/8/8/8/8/8 b - - 0 1"
perft $t03 5
foreach {blackMove whiteCapture} {
  e8d8 e7d8 e8f8 e7f8 e8d7 e6d7 e8f7 e6f7 e8e7 e6e7
} {
  set output [perft "4k3/4B3/4K3/8/8/8/8/8 b - - 0 1 moves $blackMove"]
  if {[string first "$whiteCapture: 1" $output] < 0} {
    puts stderr "T03 failed: the specified king capture after $blackMove is unavailable"
    exit 1
  }
}

# T05: король может взять своего ферзя и остаётся на целевой клетке.
set output [perft "3qk3/5Q2/8/8/2B5/8/8/4K3 b - - 0 1" 22]
if {[string first "e8d8: 1" $output] < 0} {
  puts stderr "T05 failed: own-queen capture was not generated"
  exit 1
}
send "position fen 3qk3/5Q2/8/8/2B5/8/8/4K3 b - - 0 1 moves e8d8\nd\n"
expect "3k4/5Q2/8/8/2B5/8/8/4K3 w - - 0 2" {} timeout {
  puts stderr "T05 failed: own queen was not removed after capture"
  exit 1
}

# T15: некоролевская ладья не может взять свою фигуру.
set output [perft "7k/8/8/8/8/8/B7/R3K3 w - - 0 1" 15]
if {[string first "a1a2" $output] >= 0} {
  puts stderr "T15 failed: rook captured its friendly bishop"
  exit 1
}

# T06: атака поля a8 не разрешает превращение в короля.
set output [perft "1r6/P7/7k/8/8/8/8/7K w - - 0 1"]
foreach suffix {q r b n} {
  if {[string first "a7a8$suffix: 1" $output] < 0} {
    puts stderr "T06 failed: ordinary promotion $suffix is missing"
    exit 1
  }
}
if {[string first "a7a8k" $output] >= 0} {
  puts stderr "T06 failed: attacking the promotion square allowed king promotion"
  exit 1
}

# T07: продвижение b7-b8 открывает старого короля атаке ладьи.
set output [perft "8/rP5K/7k/8/8/8/8/8 w - - 0 1"]
if {[string first "b7b8k: 1" $output] < 0} {
  puts stderr "T07 failed: promotion did not account for the opened rook line"
  exit 1
}
send "position fen 8/rP5K/7k/8/8/8/8/8 w - - 0 1 moves b7b8k\nd\n"
expect "1K6/r6K/7k" {} timeout {
  puts stderr "Promotion failed: the selected king type was not applied to the board"
  exit 1
}

# A king promotion can create an unanswerable debt; qsearch must score the
# forced loss instead of leaving bestValue at negative infinity.
send "position fen 8/rP5K/7k/8/8/8/8/8 w - - 0 1\ngo depth 1\n"
expect -re {bestmove (\S+)} {} timeout {
  puts stderr "Search failed on a king promotion with no available debt capture"
  exit 1
}

# T08: продвижение e7-e8 закрывает атаку на старого короля.
set output [perft "r6K/4P3/8/8/8/8/8/k7 w - - 0 1"]
if {[string first "e7e8k" $output] >= 0} {
  puts stderr "T08 failed: promotion ignored the line blocked by the pawn"
  exit 1
}

# T09: взятие единственного атакующего снимает основание для превращения.
set output [perft "r6K/1P6/8/8/8/8/8/k7 w - - 0 1"]
if {[string first "b7a8k" $output] >= 0} {
  puts stderr "T09 failed: captured attacker still enabled king promotion"
  exit 1
}

# T09 extension: king promotion while taking the last enemy king creates no debt.
set output [perft "k7/rP5K/8/8/8/8/8/8 w - - 0 1"]
if {[string first "b7a8k: 1" $output] < 0} {
  puts stderr "T09 failed: king promotion was incorrectly suppressed"
  exit 1
}
send "position fen k7/rP5K/8/8/8/8/8/8 w - - 0 1 moves b7a8k\nd\ngo depth 1\n"
expect "Fen: K7/r6K/8/8/8/8/8/8 b - - 0 1 lc1:-" {} timeout {
  puts stderr "T09 failed: terminal promotion created a LifeChess debt"
  exit 1
}
expect -re {bestmove (\(none\)|0000)} {} timeout {
  puts stderr "T09 failed: taking the last opposing king did not end the game"
  exit 1
}

# T10: a debt allows a choice between two target kings, but no other move.
set output [perft "K6k/8/8/8/r7/8/8/K7 b - - 0 1 lc1:w"]
if {[string first "Nodes searched: 2" $output] < 0
    || [string first "a4a1: 1" $output] < 0
    || [string first "a4a8: 1" $output] < 0} {
  puts stderr "T10 failed: debt did not allow exactly the two available king captures"
  exit 1
}
send "position fen K6k/8/8/8/r7/8/8/K7 b - - 0 1 lc1:w\ngo depth 4\n"
expect -re {bestmove a4a[18]} {} timeout {
  puts stderr "T10 failed: depth-4 search did not choose the forced king capture"
  exit 1
}

# T11: fulfilling an old debt with a king promotion creates a counter-debt.
send "position fen k1k5/1P6/8/8/8/8/r7/K7 w - - 0 1 lc1:b moves b7a8k\nd\n"
expect "Fen: K1k5/8/8/8/8/8/r7/K7 b - - 0 1 lc1:w" {} timeout {
  puts stderr "T11 failed: old debt was not replaced by the counter-debt"
  exit 1
}
set output [perft "K1k5/8/8/8/8/8/r7/K7 b - - 0 1 lc1:w"]
if {[string first "a2a1: 1" $output] < 0 || [string first "a2a8: 1" $output] < 0} {
  puts stderr "T11 failed: counter-debt could not capture either white king"
  exit 1
}

# Несколько старых королей: достаточно, чтобы после хода атакован был любой.
set output [perft "1r2r3/P7/7k/8/8/8/8/4K2K w - - 0 1"]
if {[string first "a7a8k: 1" $output] < 0} {
  puts stderr "Promotion failed: an attacked one of multiple old kings was ignored"
  exit 1
}

# Королевская рокировка разрешена, даже когда поле f1 атаковано ладьёй.
set output [perft "3rkr2/8/8/8/8/8/8/R3K2R w KQ - 0 1"]
if {[string first "e1g1: 1" $output] < 0 || [string first "e1c1: 1" $output] < 0} {
  puts stderr "Castling failed: attacked transit square was rejected"
  exit 1
}

# T12: LifeChess vertical castling follows the specified white and black squares.
set output [perft "4R2k/8/8/8/8/8/8/4K3 w V - 0 1"]
if {[string first "e1e3: 1" $output] < 0} {
  puts stderr "T12 failed: white vertical castling was not generated"
  exit 1
}
send "position fen 4R2k/8/8/8/8/8/8/4K3 w V - 0 1\nd\n"
expect "Fen: 4R2k/8/8/8/8/8/8/4K3 w V - 0 1 lc1:-" {} timeout {
  puts stderr "T12 failed: white vertical castling right did not round-trip"
  exit 1
}
perft "4R2k/8/8/8/8/8/8/4K3 w V - 0 1" 54 2
set output [perft "4R2k/8/8/8/8/3r4/8/4K3 w V - 0 1"]
if {[string first "e1e3: 1" $output] < 0} {
  puts stderr "T12 failed: an attacked vertical-castling destination was rejected"
  exit 1
}
send "position fen 4R2k/8/8/8/8/8/8/4K3 w V - 0 1 moves e1e3\nd\n"
expect "Fen: 7k/8/8/8/8/4K3/4R3/8 b - - 1 1 lc1:-" {} timeout {
  puts stderr "T12 failed: white vertical castling applied wrong destinations"
  exit 1
}

set output [perft "4k3/8/8/8/8/8/8/4r2K b v - 0 1"]
if {[string first "e8e6: 1" $output] < 0} {
  puts stderr "T12 failed: black vertical castling was not generated"
  exit 1
}
perft "4k3/8/8/8/8/8/8/4r2K b v - 0 1" 54 2
send "position fen 4k3/8/8/8/8/8/8/4r2K b v - 0 1 moves e8e6\nd\n"
expect "Fen: 8/4r3/4k3/8/8/8/8/7K w - - 1 2 lc1:-" {} timeout {
  puts stderr "T12 failed: black vertical castling applied wrong destinations"
  exit 1
}

# The path squares e2-e7 must be empty; the source squares e1 and e8 are exempt.
set output [perft "4R2k/8/8/4b3/8/8/8/4K3 w V - 0 1"]
if {[string first "e1e3" $output] >= 0} {
  puts stderr "T12 failed: an occupied vertical castling path was ignored"
  exit 1
}

# T13: claimable 50-move and repetition thresholds must not auto-end search.
send "position fen 7k/8/8/8/8/8/8/K6R w - - 100 51\ngo depth 1\n"
expect -re {bestmove [a-h][1-8][a-h][1-8]} {} timeout {
  puts stderr "T13 failed: claimable 50-move threshold auto-ended the game"
  exit 1
}
send "position startpos moves g1f3 g8f6 f3g1 f6g8 g1f3 g8f6 f3g1 f6g8\ngo depth 1\n"
expect -re {bestmove [a-h][1-8][a-h][1-8]} {} timeout {
  puts stderr "T13 failed: threefold repetition auto-ended the game"
  exit 1
}

# Стандартная рокировка не считается взятием собственных фигур.
send "setoption name UCI_Variant value chess\nisready\n"
expect "readyok" {} timeout { exit 1 }
send "position fen r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq -\ngo perft 2\n"
expect "Nodes searched: 2039" {} timeout {
  puts stderr "Chess regression: standard perft position differs at depth 2"
  exit 1
}

# Захват последнего короля завершает партию немедленно.
send "setoption name UCI_Variant value lifechess\nisready\n"
expect "readyok" {} timeout { exit 1 }

# T04: execute the owner's tactical line exactly, then verify search sees it.
set t04 "8/1P5q/7k/8/8/8/3r3K/2B5 w - - 0 1"
send "position fen $t04 moves b7b8k d2h2 c1h6\nd\n"
expect "Fen: 1K6/7q/7B/8/8/8/7r/8 b - - 0 2 lc1:-" {} timeout {
  puts stderr "T04 failed: the forced debt line did not end with White taking the last king"
  exit 1
}
send "setoption name Threads value 1\nsetoption name Hash value 16\nsetoption name Use NNUE value false\nposition fen $t04\ngo depth 5\n"
expect "bestmove" {} timeout {
  puts stderr "T04 search failed to return a legal action within the fixed depth budget"
  exit 1
}
set searchOutput $expect_out(buffer)
set scores [regexp -all -inline {score (cp|mate) (-?[0-9]+)} $searchOutput]
set finalScore [lindex $scores end]
if {$finalScore eq "" || $finalScore <= 0} {
  puts stderr "T04 search did not evaluate the position as winning at depth 5"
  exit 1
}

send "position fen 8/8/8/8/8/8/4k3/4K3 b - - 0 1\ngo depth 1\n"
expect "bestmove e2e1" {} timeout {
  puts stderr "Terminal capture failed: the final opposing king was not taken"
  exit 1
}

# Начало хода без собственного короля — проигрыш, а не пат.
send "position fen 7K/8/8/8/8/8/8/8 b - - 0 1\ngo depth 1\n"
expect -re {bestmove (\(none\)|0000)} {} timeout {
  puts stderr "Extinction failed: side without a king was allowed to continue"
  exit 1
}

send "quit\n"
expect eof
wait
log_user 1
puts "LifeChess core tests passed"
