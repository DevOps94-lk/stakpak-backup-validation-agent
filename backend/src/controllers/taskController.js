const pool = require('../config/db');
const { validationResult } = require('express-validator');

const getAllTasks = async (req, res, next) => {
  try {
    const [rows] = await pool.query('SELECT * FROM tasks ORDER BY created_at DESC');
    res.json({ success: true, data: rows });
  } catch (err) {
    next(err);
  }
};

const getTaskById = async (req, res, next) => {
  try {
    const [rows] = await pool.query('SELECT * FROM tasks WHERE id = ?', [req.params.id]);
    if (rows.length === 0) return res.status(404).json({ success: false, message: 'Task not found' });
    res.json({ success: true, data: rows[0] });
  } catch (err) {
    next(err);
  }
};

const createTask = async (req, res, next) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) return res.status(422).json({ success: false, errors: errors.array() });

  try {
    const { title, description, status } = req.body;
    const [result] = await pool.query(
      'INSERT INTO tasks (title, description, status) VALUES (?, ?, ?)',
      [title, description || null, status || 'pending']
    );
    const [rows] = await pool.query('SELECT * FROM tasks WHERE id = ?', [result.insertId]);
    res.status(201).json({ success: true, data: rows[0] });
  } catch (err) {
    next(err);
  }
};

const updateTask = async (req, res, next) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) return res.status(422).json({ success: false, errors: errors.array() });

  try {
    const { title, description, status } = req.body;
    const [result] = await pool.query(
      'UPDATE tasks SET title = ?, description = ?, status = ? WHERE id = ?',
      [title, description || null, status, req.params.id]
    );
    if (result.affectedRows === 0) return res.status(404).json({ success: false, message: 'Task not found' });
    const [rows] = await pool.query('SELECT * FROM tasks WHERE id = ?', [req.params.id]);
    res.json({ success: true, data: rows[0] });
  } catch (err) {
    next(err);
  }
};

const deleteTask = async (req, res, next) => {
  try {
    const [result] = await pool.query('DELETE FROM tasks WHERE id = ?', [req.params.id]);
    if (result.affectedRows === 0) return res.status(404).json({ success: false, message: 'Task not found' });
    res.json({ success: true, message: 'Task deleted successfully' });
  } catch (err) {
    next(err);
  }
};

module.exports = { getAllTasks, getTaskById, createTask, updateTask, deleteTask };
