const express = require('express');
const router = express.Router();
const { body } = require('express-validator');
const { getAllTasks, getTaskById, createTask, updateTask, deleteTask } = require('../controllers/taskController');

const taskValidation = [
  body('title').trim().notEmpty().withMessage('Title is required').isLength({ max: 255 }),
  body('status').optional().isIn(['pending', 'in_progress', 'done']).withMessage('Invalid status'),
];

router.get('/', getAllTasks);
router.get('/:id', getTaskById);
router.post('/', taskValidation, createTask);
router.put('/:id', taskValidation, updateTask);
router.delete('/:id', deleteTask);

module.exports = router;
