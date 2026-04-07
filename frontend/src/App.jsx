import { Toaster } from 'react-hot-toast';
import HomePage from './pages/HomePage';

export default function App() {
  return (
    <>
      <Toaster position="top-right" />
      <HomePage />
    </>
  );
}
