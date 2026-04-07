import TaskCard from './TaskCard';

export default function TaskList({ tasks, onEdit, onDelete, loading }) {
  if (loading) return <p style={styles.msg}>Loading tasks...</p>;
  if (tasks.length === 0) return <p style={styles.msg}>No tasks yet. Add one above!</p>;

  return (
    <div style={styles.grid}>
      {tasks.map((task) => (
        <TaskCard key={task.id} task={task} onEdit={onEdit} onDelete={onDelete} />
      ))}
    </div>
  );
}

const styles = {
  grid: { display: 'grid', gap: '0.8rem' },
  msg: { textAlign: 'center', color: '#888', marginTop: '2rem' },
};
