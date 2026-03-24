# simple cache placeholder
CACHE = {}

def get(key):
    return CACHE.get(key)

def set(key, value):
    CACHE[key] = value
