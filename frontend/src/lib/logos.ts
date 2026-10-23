// The logos of the Create VM window. They are files bundled with the panel (the page's content security policy allows only its own files), so none is ever fetched from another site.
import almalinux from '../assets/logos/almalinux.svg'
import alpinelinux from '../assets/logos/alpinelinux.svg'
import debian from '../assets/logos/debian.svg'
import docker from '../assets/logos/docker.svg'
import fedora from '../assets/logos/fedora.svg'
import hermes from '../assets/logos/hermes.svg'
import nodejs from '../assets/logos/nodedotjs.svg'
import ollama from '../assets/logos/ollama.svg'
import openclaw from '../assets/logos/openclaw.svg'
import python from '../assets/logos/python.svg'
import rockylinux from '../assets/logos/rockylinux.svg'
import ubuntu from '../assets/logos/ubuntu.svg'

export const LOGOS = { almalinux, alpinelinux, debian, docker, fedora, hermes, nodejs, ollama, openclaw, python, rockylinux, ubuntu } as const

export type LogoName = keyof typeof LOGOS
