// Drop-down menus.

// ---- menus (plan 6 #7) ----------------------------------------------------
//
// The console had twenty-odd controls above the table, most of them doing
// nothing until something was selected. They live in two menus now, and the
// selection-dependent ones only exist while there is a selection.

export function toggleMenu(event, id){
  event.stopPropagation();
  const menu = document.getElementById(id);
  const wasOpen = !menu.classList.contains('hidden');
  closeMenus();
  if (!wasOpen) menu.classList.remove('hidden');
}

export function closeMenus(){
  for (const m of document.querySelectorAll('.menu')) m.classList.add('hidden');
}

/// Runs a menu item and closes the menu — every item wants both, and forgetting
/// the second half leaves the menu hanging over whatever it just opened.
export function pick(fn){
  closeMenus();
  fn();
}
