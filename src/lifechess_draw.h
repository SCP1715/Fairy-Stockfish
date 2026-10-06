/*
  Fairy-Stockfish, a UCI chess variant playing engine derived from Stockfish
  Copyright (C) 2026 LifeChess contributors

  This file is part of Fairy-Stockfish.
*/

#ifndef LIFECHESS_DRAW_H_INCLUDED
#define LIFECHESS_DRAW_H_INCLUDED

#include <algorithm>

#include "types.h"

namespace Stockfish {
namespace LifeChess {

enum class DrawDecision { Continue, Claim, Accept, Decline, Offer, ClaimBareKings };

// Material phase follows the usual 24-point scale: queen=4, rook=2,
// bishop/knight=1. Voluntary offers move from -1000 cp in the opening to 0 cp
// in the endgame. Claims and accepts use the separately approved 0 cp limit.
inline Value draw_score_threshold(int materialPhase) {
    const int phase = std::max(0, std::min(24, materialPhase));
    return Value(-(1000 * phase) / 24);
}

inline const char* claim_reason(bool repetition, bool fiftyMoves) {
    if (repetition) return "repetition";
    if (fiftyMoves) return "fifty_moves";
    return "unknown";
}

// Ignore a near-threshold score from the first two completed iterations. A
// clearly losing score may still trigger an early offer in the opening.
inline bool draw_offer_is_stable(Value score, Value threshold, int completedDepth) {
    return completedDepth >= 3 || score <= threshold - Value(250);
}

// `score` is from the engine's point of view. A positive score is winning;
// `drawThreshold` is the phase-sensitive limit for initiating/claiming a draw.
inline DrawDecision draw_decision(Value score, bool opponentOffered,
                                  bool claimable, bool offerAlreadySent,
                                  bool analysisMode, Value drawThreshold,
                                  bool bareKingsClaimable = false,
                                  bool offerScoreStable = true) {
    if (analysisMode)
        return DrawDecision::Continue;

    if (bareKingsClaimable)
        return DrawDecision::ClaimBareKings;

    if (claimable && score <= VALUE_DRAW)
        return DrawDecision::Claim;

    if (opponentOffered)
        return score <= VALUE_DRAW ? DrawDecision::Accept : DrawDecision::Decline;
    if (!offerAlreadySent && offerScoreStable && score <= drawThreshold)
        return DrawDecision::Offer;
    return DrawDecision::Continue;
}

} // namespace LifeChess
} // namespace Stockfish

#endif // LIFECHESS_DRAW_H_INCLUDED
