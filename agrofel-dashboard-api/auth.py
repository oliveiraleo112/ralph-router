from fastapi import Header, HTTPException

async def validate_token(authorization: str | None = Header(None)):
    if not authorization:
        raise HTTPException(status_code=401, detail="Missing Authorization")
    if authorization != "Bearer test-token":
        raise HTTPException(status_code=403, detail="Invalid token")
    return True
