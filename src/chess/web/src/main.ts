import { mount } from 'svelte';
import './theme/style.css';
import './styles.css';
import App from './App.svelte';

const target = document.getElementById('app');
if (!target) throw new Error('chess: #app not found');

mount(App, { target });
