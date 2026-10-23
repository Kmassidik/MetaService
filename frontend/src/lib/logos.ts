// The logos of the Create VM window. They are files bundled with the panel (the page's content security policy allows only its own files), so none is ever fetched from another site.
import almalinux from '../assets/logos/almalinux.svg'
import alpinelinux from '../assets/logos/alpinelinux.svg'
import debian from '../assets/logos/debian.svg'
import fedora from '../assets/logos/fedora.svg'
import hermes from '../assets/logos/hermes.webp'
import openclaw from '../assets/logos/openclaw.svg'
import rockylinux from '../assets/logos/rockylinux.svg'
import ubuntu from '../assets/logos/ubuntu.svg'

export const LOGOS = { almalinux, alpinelinux, debian, fedora, hermes, openclaw, rockylinux, ubuntu } as const

export type LogoName = keyof typeof LOGOS
