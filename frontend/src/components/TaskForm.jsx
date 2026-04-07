import { useState, useEffect } from 'react';

const EMPTY = { title: '', description: '', status: 'pending' };

export default function TaskForm({ onSubmit, editingTask, onCancel }) {
  const [form, setForm] = useState(EMPTY);

  useEffect(() => {
    setForm(editingTask ? { title: editingTask.title, description: editingTask.description || '', status: editingTask.status } : EMPTY);
  }, [editingTask]);

  const handleChange = (e) => setForm((prev) => ({ ...prev, [e.target.name]: e.target.value }));

  const handleSubmit = (e) => {
    e.preventDefault();
    if (!form.title.trim()) return;
    onSubmit(form);
    setForm(EMPTY);
  };

  return (
    <form onSubmit={handleSubmit} style={styles.form}>
      <h2 style={styles.heading}>{editingTask ? 'Edit Task' : 'New Task'}</h2>

      <input
        name="title"
        value={form.title}
        onChange={handleChange}
        placeholder="Task title *"
        required
        style={styles.input}
      />

      <textarea
        name="description"
        value={form.description}
        onChange={handleChange}
        placeholder="Description (optional)"
        rows={3}
        style={{ ...styles.input, resize: 'vertical' }}
      />

      <select name="status" value={form.status} onChange={handleChange} style={styles.input}>
        <option value="pending">Pending</option>
        <option value="in_progress">In Progress</option>
        <option value="done">Done</option>
      </select>

      <div style={styles.btnRow}>
        <button type="submit" style={styles.btnPrimary}>
          {editingTask ? 'Update' : 'Add Task'}
        </button>
        {editingTask && (
          <button type="button" onClick={onCancel} style={styles.btnSecondary}>
            Cancel
          </button>
        )}
      </div>
    </form>
  );
}

const styles = {
  form: { background: '#fff', padding: '1.5rem', borderRadius: 8, boxShadow: '0 2px 8px rgba(0,0,0,0.08)', marginBottom: '2rem' },
  heading: { margin: '0 0 1rem', fontSize: '1.2rem', color: '#333' },
  input: { display: 'block', width: '100%', padding: '0.6rem 0.8rem', marginBottom: '0.8rem', border: '1px solid #ddd', borderRadius: 6, fontSize: '0.95rem', boxSizing: 'border-box' },
  btnRow: { display: 'flex', gap: '0.5rem' },
  btnPrimary: { flex: 1, padding: '0.6rem', background: '#4f46e5', color: '#fff', border: 'none', borderRadius: 6, cursor: 'pointer', fontWeight: 600 },
  btnSecondary: { padding: '0.6rem 1rem', background: '#e5e7eb', color: '#333', border: 'none', borderRadius: 6, cursor: 'pointer' },
};
