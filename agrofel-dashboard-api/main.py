from fastapi import FastAPI, Header, HTTPException

app = FastAPI()

@app.get("/api/dashboard/summary")
def summary(authorization: str | None = Header(None)):
    # Minimal placeholder: return 401 if Authorization header missing or invalid
    if not authorization:
        raise HTTPException(status_code=401, detail="Missing Authorization")
    if authorization != "Bearer test-token":
        # In real deployment, validate against Chatwoot
        raise HTTPException(status_code=403, detail="Invalid token")
    return {"status":"ok","data":{"messages":0}}

@app.get("/")
def root():
    return {"status":"dashboard-api"}
