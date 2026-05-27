# order-service/app.py
# Order processing - FastAPI (async, modern, auto-generates OpenAPI docs)
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from typing import List, Optional
from datetime import datetime
import os
import uuid
import httpx
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger('order-service')

app = FastAPI(title='CloudVault Order Service', version='1.0.0')

PRODUCT_SERVICE_URL = os.getenv('PRODUCT_SERVICE_URL', 'http://localhost:3002')
CART_SERVICE_URL = os.getenv('CART_SERVICE_URL', 'http://localhost:3003')

# In-memory order store (PostgreSQL on Day 3)
orders_db = {}

class OrderItem(BaseModel):
    product_id: int
    quantity: int

class OrderRequest(BaseModel):
    user_id: str
    items: List[OrderItem]

class Order(BaseModel):
    id: str
    user_id: str
    items: List[OrderItem]
    total: float
    status: str
    created_at: str

@app.get('/health')
async def health():
    return {'status': 'healthy', 'service': 'order-service'}

@app.get('/ready')
async def ready():
    return {'ready': True}

@app.post('/orders', response_model=Order)
async def create_order(order_req: OrderRequest):
    order_id = str(uuid.uuid4())
    total = 0.0

    # Fetch product prices to compute total
    async with httpx.AsyncClient(timeout=5.0) as client:
        for item in order_req.items:
            try:
                resp = await client.get(f'{PRODUCT_SERVICE_URL}/products/{item.product_id}')
                if resp.status_code != 200:
                    raise HTTPException(404, f'Product {item.product_id} not found')
                product = resp.json()
                total += product['price'] * item.quantity
            except httpx.RequestError as e:
                logger.error(f'product-service unreachable: {e}')
                raise HTTPException(503, 'Product service unavailable')

    order = {
        'id': order_id,
        'user_id': order_req.user_id,
        'items': [item.dict() for item in order_req.items],
        'total': round(total, 2),
        'status': 'pending',
        'created_at': datetime.utcnow().isoformat()
    }
    orders_db[order_id] = order
    logger.info(f'Created order {order_id} for user {order_req.user_id}, total ${total}')
    return order

@app.get('/orders/{order_id}', response_model=Order)
async def get_order(order_id: str):
    if order_id not in orders_db:
        raise HTTPException(404, 'Order not found')
    return orders_db[order_id]

@app.get('/orders/user/{user_id}')
async def list_user_orders(user_id: str):
    user_orders = [o for o in orders_db.values() if o['user_id'] == user_id]
    return user_orders
