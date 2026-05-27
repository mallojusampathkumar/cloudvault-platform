# product-service/app.py
# Catalog microservice - returns product listings
from flask import Flask, jsonify, request
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST
import time
import os
import logging

# Configure structured logging (production pattern)
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(name)s: %(message)s'
)
logger = logging.getLogger('product-service')

app = Flask(__name__)

# Prometheus metrics - we'll scrape these on Day 6
REQUEST_COUNT = Counter(
    'product_service_requests_total',
    'Total HTTP requests',
    ['method', 'endpoint', 'status']
)
REQUEST_LATENCY = Histogram(
    'product_service_request_duration_seconds',
    'Request latency in seconds',
    ['method', 'endpoint']
)

# Mock product catalog (we'll replace with PostgreSQL on Day 3)
PRODUCTS = [
    {"id": 1, "name": "Wireless Mouse", "price": 25.99, "stock": 150, "category": "electronics"},
    {"id": 2, "name": "Mechanical Keyboard", "price": 89.99, "stock": 75, "category": "electronics"},
    {"id": 3, "name": "USB-C Hub", "price": 34.50, "stock": 200, "category": "electronics"},
    {"id": 4, "name": "Coffee Mug", "price": 12.00, "stock": 500, "category": "kitchen"},
    {"id": 5, "name": "Notebook", "price": 8.50, "stock": 1000, "category": "stationery"},
]

@app.before_request
def start_timer():
    request.start_time = time.time()

@app.after_request
def record_metrics(response):
    if hasattr(request, 'start_time'):
        latency = time.time() - request.start_time
        REQUEST_LATENCY.labels(request.method, request.path).observe(latency)
        REQUEST_COUNT.labels(request.method, request.path, response.status_code).inc()
    return response

@app.route('/health')
def health():
    return jsonify({
        'status': 'healthy',
        'service': 'product-service',
        'version': '1.0.0'
    }), 200

@app.route('/ready')
def ready():
    # In real apps: check database connection
    return jsonify({'ready': True}), 200

@app.route('/metrics')
def metrics():
    return generate_latest(), 200, {'Content-Type': CONTENT_TYPE_LATEST}

@app.route('/products', methods=['GET'])
def list_products():
    category = request.args.get('category')
    if category:
        filtered = [p for p in PRODUCTS if p['category'] == category]
        return jsonify(filtered)
    return jsonify(PRODUCTS)

@app.route('/products/<int:product_id>', methods=['GET'])
def get_product(product_id):
    product = next((p for p in PRODUCTS if p['id'] == product_id), None)
    if not product:
        return jsonify({'error': 'Product not found'}), 404
    return jsonify(product)

if __name__ == '__main__':
    port = int(os.environ.get('PORT', 3002))
    logger.info(f'Starting product-service on port {port}')
    app.run(host='0.0.0.0', port=port)
