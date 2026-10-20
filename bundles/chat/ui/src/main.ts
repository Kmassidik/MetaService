import { mount } from 'svelte'
import App from './App.svelte'
import './style.css'
import './theme-dark.css'

const target = document.getElementById('app')
if (!target) throw new Error('The page has no #app element to mount the chat screen into.')

mount(App, { target })
