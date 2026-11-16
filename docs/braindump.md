I want to build a native macOS app written in Swift that will help me in running dev servers for my web apps built in Laravel, Vue.js, etc. 

I would like to be able to define projects that I could then populate with the commands needed to run dev servers for these projects, for example:
- npm run dev
- php artisan dev
- php artisan schedule:work
- queue:listen long --tries=1 --timeout=0
- NODE_ENV=development npm run dev
- etc.

I should be able to start all of the commands for a single project with a single click. Same goes for restarts, quitting and viewing the their status.

I'll also want to start/restart/quit these processes one by one.

The set of commands should be configurable on a project-by-project basis.
It would be nice to have autodiscovery - after pointing to the folder, the app should check the contents of composer.json, package.json, etc. and propose an initial list (with checkboxes?) that contains the most common dev commands for each of the discovered stacks.

It would be nice to he an MCP built in, so the agent could perform these actions themself (e.g. after performing a code change that requires to restart the queue)

Sometimes I'll want to see their output (for debugging purposes). Maybe we could use [libghostty-vt: libghostty-vt](https://lib.ghostty.org/vt/) for this?

The app should also be accessible from a menubar (enabling/disabling of this feature should be configurable from the settings view) and act similiarly to [F-Bar](https://laravel-forge-menubar.com/) https://img.publicera.net/B4BS177v6OzH8dN135YpkH5S2nk=/fit-in/1200x1000/smart/filters:format(webp)/https%3A%2F%2Ffiles.publicera.net%2F99bcf85c-192d-4ebf-bfa9-da37d57037fc%2Fcleanshot-2026-03-01-at-201228-at-2x-1lsj.png.

I'd also like to get native system notfications when a command (or a while project) starts, restarts, or quits, and when a child process crashes.