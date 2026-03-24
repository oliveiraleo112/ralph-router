from fastapi import APIRouter, Depends
from auth import validate_token
from fastapi import APIRouter, Depends

router = APIRouter()

@router.get('/')
async def dashboard_root(token: bool = Depends(validate_token)):
    return {"status":"ok","data":{}}
