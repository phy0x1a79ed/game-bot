from coms.bot import Bot
from coms.protocol import MoveRequest


class NaiveBot(Bot):
    name = "naive"
    version = "1"

    def choose_move(self, request: MoveRequest) -> str:
        return self.rng.choice(request.legal_moves)


if __name__ == "__main__":
    NaiveBot.main()
