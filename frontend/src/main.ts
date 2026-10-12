import './app.css'
import { mount } from 'svelte'
import App from './App.svelte'

const target = document.getElementById('app')
if (!target) throw new Error('index.html has no #app to mount the panel in')

mount(App, { target })
