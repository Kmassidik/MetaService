// The logos of the Create VM window, of the Docker services in the Building and of the three systems on the Share a PC page. They are files bundled with the panel (the page's content security policy allows only its own files), so none is ever fetched from another site.
import almalinux from '../assets/logos/almalinux.svg'
import alpinelinux from '../assets/logos/alpinelinux.svg'
import apple from '../assets/logos/apple.svg'
import debian from '../assets/logos/debian.svg'
import docker from '../assets/logos/docker.svg'
import fedora from '../assets/logos/fedora.svg'
import hermes from '../assets/logos/hermes.webp'
import linux from '../assets/logos/linux.svg'
import openclaw from '../assets/logos/openclaw.svg'
import rockylinux from '../assets/logos/rockylinux.svg'
import ubuntu from '../assets/logos/ubuntu.svg'
import windows from '../assets/logos/windows.svg'

export const LOGOS = { almalinux, alpinelinux, apple, debian, docker, fedora, hermes, linux, openclaw, rockylinux, ubuntu, windows } as const

export type LogoName = keyof typeof LOGOS
