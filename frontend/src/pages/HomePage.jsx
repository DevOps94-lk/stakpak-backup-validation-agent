import { useState, useEffect, useCallback } from 'react';
import toast from 'react-hot-toast';
import TaskForm from '../components/TaskForm';
import TaskList from '../components/TaskList';
import { getTasks, createTask, updateTask, deleteTask } from '../api/taskApi';

export default function HomePage() {
  const [tasks, setTasks] = useState([]);
  const [loading, setLoading] = useState(true);
  const [editingTask, setEditingTask] = useState(null);

  const fetchTasks = useCallback(async () => {
    try {
      const { data } = await getTasks();
      setTasks(data.data);
    } catch {
      toast.error('Failed to load tasks');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { fetchTasks(); }, [fetchTasks]);

  const handleSubmit = async (form) => {
    try {
      if (editingTask) {
        const { data } = await updateTask(editingTask.id, form);
        setTasks((prev) => prev.map((t) => (t.id === editingTask.id ? data.data : t)));
        toast.success('Task updated');
        setEditingTask(null);
      } else {
        const { data } = await createTask(form);
        setTasks((prev) => [data.data, ...prev]);
        toast.success('Task created');
      }
    } catch {
      toast.error('Something went wrong');
    }
  };

  const handleDelete = async (id) => {
    if (!window.confirm('Delete this task?')) return;
    try {
      await deleteTask(id);
      setTasks((prev) => prev.filter((t) => t.id !== id));
      toast.success('Task deleted');
    } catch {
      toast.error('Failed to delete task');
    }
  };

  return (
    <main style={styles.main}>
      <h1 style={styles.appTitle}>Task Manager</h1>
      <TaskForm onSubmit={handleSubmit} editingTask={editingTask} onCancel={() => setEditingTask(null)} />
      <TaskList tasks={tasks} onEdit={setEditingTask} onDelete={handleDelete} loading={loading} />
    </main>
  );
}

const styles = {
  main: { maxWidth: 680, margin: '0 auto', padding: '2rem 1rem' },
  appTitle: { textAlign: 'center', marginBottom: '1.5rem', color: '#4f46e5', fontSize: '1.8rem' },
};
