from pydantic import BaseModel

class Summary(BaseModel):
    messages: int = 0
