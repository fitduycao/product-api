const express = require('express');
const controller = require('../controllers/productController');

const router = express.Router();

router.post('/', controller.createProduct);
router.get('/', controller.getProducts);
router.get('/:pid', controller.getProduct);
router.put('/:pid', controller.updateProduct);
router.patch('/:pid', controller.updateProduct);
router.delete('/:pid', controller.deleteProduct);

module.exports = router;
