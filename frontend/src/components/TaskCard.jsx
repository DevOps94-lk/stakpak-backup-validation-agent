const STATUS_STYLES = {
  pending:     { background: '#fef3c7', color: '#92400e' },
  in_progress: { background: '#dbeafe', color: '#1e40af' },
  done:        { background: '#d1fae5', color: '#065f46' },
};

export default function TaskCard({ task, onEdit, onDelete }) {
  return (
    <div style={styles.card}>
      <div style={styles.top}>
        <h3 style={styles.title}>{task.title}</h3>
        <span style={{ ...styles.badge, ...STATUS_STYLES[task.status] }}>
          {task.status.replace('_', ' ')}
        </span>
      </div>

      {task.description && <p style={styles.desc}>{task.description}</p>}

      <div style={styles.footer}>
        <small style={styles.date}>{new Date(task.created_at).toLocaleDateString()}</small>
        <div style={styles.actions}>
          <button onClick={() => onEdit(task)} style={styles.btnEdit}>Edit</button>
          <button onClick={() => onDelete(task.id)} style={styles.btnDelete}>Delete</button>
        </div>
      </div>
    </div>
  );
}

const styles = {
  card: { background: '#fff', border: '1px solid #e5e7eb', borderRadius: 8, padding: '1rem 1.2rem', boxShadow: '0 1px 4px rgba(0,0,0,0.05)' },
  top: { display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', gap: '0.5rem' },
  title: { margin: 0, fontSize: '1rem', color: '#111', flex: 1 },
  badge: { padding: '2px 10px', borderRadius: 20, fontSize: '0.75rem', fontWeight: 600, whiteSpace: 'nowrap', textTransform: 'capitalize' },
  desc: { margin: '0.5rem 0 0', fontSize: '0.88rem', color: '#555' },
  footer: { display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginTop: '0.8rem' },
  date: { color: '#aaa', fontSize: '0.78rem' },
  actions: { display: 'flex', gap: '0.4rem' },
  btnEdit: { padding: '4px 12px', background: '#f0f0f0', border: 'none', borderRadius: 5, cursor: 'pointer', fontSize: '0.85rem' },
  btnDelete: { padding: '4px 12px', background: '#fee2e2', color: '#b91c1c', border: 'none', borderRadius: 5, cursor: 'pointer', fontSize: '0.85rem' },
};
