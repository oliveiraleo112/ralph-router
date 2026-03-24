# chatwoot service stub
async def get_profile(token: str):
    # In real implementation, call Chatwoot /api/v1/profile
    if token == "test-token":
        return {"name":"test"}
    return None
