import os
import time
import sys
import shutil
import json
import hashlib

# --- KONFIGURACJA I ŚCIEŻKI (LINUX VERSION) ---
# Ustawiamy bazę danych w folderze systemowym, nie lokalnym
BASE_PATH = "/var/comrade_data" 
USER_DB_FILE = os.path.join(BASE_PATH, ".users.json")

# --- MENEDŻER KOLORÓW ---
class KolorManager:
    AKTYWNE = True
    def c(self, kod): return kod if self.AKTYWNE else ''
    @property
    def CZERWONY(self): return self.c('\033[91m')
    @property
    def ZOLTY(self): return self.c('\033[93m')
    @property
    def SZARY(self): return self.c('\033[90m')
    @property
    def RESET(self): return self.c('\033[0m')
    @property
    def BOLD(self): return self.c('\033[1m')

K = KolorManager()

# --- ZMIENNE GLOBALNE ---
CURRENT_PATH = BASE_PATH
TRYB_POKAZ_UKRYTE = False
OBECNY_LOGIN = None
OBECNY_ROLA = None

# --- BEZPIECZEŃSTWO ---

def szyfruj(haslo):
    if not haslo: return ""
    return hashlib.sha256(haslo.encode('utf-8')).hexdigest()

# --- NARZĘDZIA PLIKOWE ---

def inicjalizacja_systemu():
    if not os.path.exists(BASE_PATH):
        try:
            os.makedirs(BASE_PATH)
            with open(os.path.join(BASE_PATH, "readme.txt"), "w", encoding='utf-8') as f:
                f.write("Witaj w Comrade OS 1.0.\nWpisz 'ZAMKNIJ' aby wyjsc z edytora.")
        except OSError as e:
            print(f"Błąd krytyczny: {e}")
            sys.exit(1)

def laduj_uzytkownikow():
    if os.path.exists(USER_DB_FILE):
        try:
            with open(USER_DB_FILE, 'r', encoding='utf-8') as f:
                return json.load(f)
        except: return {}
    return {}

def zapisz_uzytkownikow(db):
    with open(USER_DB_FILE, 'w', encoding='utf-8') as f:
        json.dump(db, f)

# --- INTERFEJS ---

def wyczysc_ekran():
    os.system('cls' if os.name == 'nt' else 'clear')

def logo():
    print(K.CZERWONY + "★ COMRADE OS 1.0 ★" + K.RESET)
    if OBECNY_LOGIN:
        print(f"Zalogowano: {K.BOLD}{OBECNY_LOGIN}{K.RESET} [{OBECNY_ROLA}]")

def pauza():
    try: input(f"\n{K.SZARY}[Enter...]{K.RESET}")
    except: input("\n[Enter...]")

def pokaz_komendy():
    cmds = ["utworz", "otworz", "wyjdz", "usun", "edytuj", 
            "stworz-folder", "ukryj", "pokaz", "pokaz_ukryte",
            "ustawienia", "zamknij"]
    print(f"{K.SZARY}KOMENDY: [{' | '.join(cmds)}]{K.RESET}")
    print("-" * 50)

def widok_pulpitu():
    folder_name = os.path.basename(CURRENT_PATH)
    if CURRENT_PATH == BASE_PATH: folder_name = "ROOT"
    
    print(K.ZOLTY + f"#######{folder_name.upper()}#######" + K.RESET)
    print("[")
    
    try:
        elementy = os.listdir(CURRENT_PATH)
        pusto = True
        elementy.sort(key=lambda x: (not os.path.isdir(os.path.join(CURRENT_PATH, x)), x))

        for nazwa in elementy:
            if nazwa == ".users.json": continue
            ukryty = nazwa.startswith(".")
            
            if ukryty and not TRYB_POKAZ_UKRYTE: continue

            pusto = False
            pelna_sciezka = os.path.join(CURRENT_PATH, nazwa)
            prefix = ""
            display_name = "*" + nazwa[1:] if ukryty else nazwa
            
            if os.path.isdir(pelna_sciezka):
                print(f"-/{display_name}")
            else:
                print(f"-{display_name}")

        if pusto: print(" (pusto)")
    except PermissionError:
        print(f"{K.CZERWONY} BŁĄD: Brak dostępu.{K.RESET}")
    
    print("]")
    print("-" * len(f"#######{folder_name}#######"))

# --- LOGIKA SYSTEMU ---

def rejestracja():
    db = laduj_uzytkownikow()
    if db: return
    
    wyczysc_ekran()
    print(K.CZERWONY + "REJESTRACJA ADMINISTRATORA" + K.RESET)
    while True:
        login = input("Login: ").strip()
        if not login: continue
        p1 = input("Hasło: ").strip()
        p2 = input("Powtórz: ").strip()
        
        if p1 != p2:
            print("Hasła nie pasują.")
            continue
            
        if not p1:
            print(f"{K.CZERWONY}OSTRZEŻENIE: Brak hasła.{K.RESET}")
            if input("Kontynuować mimo ryzyka? (Y/N): ").upper() != 'Y':
                continue
        
        zaszyfrowane_haslo = szyfruj(p1)
        db[login] = {"haslo": zaszyfrowane_haslo, "rola": "admin", "root_dir": "/"}
        zapisz_uzytkownikow(db)
        print("Zarejestrowano (Hasło zaszyfrowane).")
        time.sleep(1)
        break

def logowanie():
    global OBECNY_LOGIN, OBECNY_ROLA, CURRENT_PATH
    rejestracja()
    
    while True:
        wyczysc_ekran()
        print(K.CZERWONY + "LOGOWANIE" + K.RESET)
        l = input("Login: ").strip()
        h = input("Hasło: ").strip()
        
        db = laduj_uzytkownikow()
        h_hash = szyfruj(h)
        
        if l in db and db[l]["haslo"] == h_hash:
            OBECNY_LOGIN = l
            OBECNY_ROLA = db[l]["rola"]
            
            CURRENT_PATH = BASE_PATH
            if OBECNY_ROLA == "gosc":
                user_path = os.path.join(BASE_PATH, "users", l)
                os.makedirs(user_path, exist_ok=True)
                CURRENT_PATH = user_path
            
            print("Dostęp przyznany.")
            time.sleep(0.5)
            break
        else:
            print("Błąd logowania.")
            time.sleep(1)

# --- KOMENDY ---

def cmd_utworz(nazwa):
    if not nazwa: return
    path = os.path.join(CURRENT_PATH, nazwa)
    if os.path.exists(path):
        print("Plik już istnieje.")
        return
    try:
        with open(path, 'w', encoding='utf-8') as f: pass
        print(f"Utworzono: {nazwa}")
    except Exception as e: print(f"Błąd: {e}")

def cmd_stworz_folder(nazwa):
    if not nazwa: return
    path = os.path.join(CURRENT_PATH, nazwa)
    try:
        os.mkdir(path)
        print(f"Utworzono folder: {nazwa}")
    except FileExistsError: print("Folder już istnieje.")
    except Exception as e: print(f"Błąd: {e}")

def cmd_edytuj(nazwa):
    if not nazwa: return
    path = os.path.join(CURRENT_PATH, nazwa)
    if not os.path.isfile(path):
        print("To nie jest plik.")
        return
    
    # --- ZMIANA W EDYTORZE ---
    print(f"{K.ZOLTY}EDYCJA (Wpisz 'ZAMKNIJ' w nowej linii aby zapisac):{K.RESET}")
    
    try:
        with open(path, 'r', encoding='utf-8') as f:
            print(f.read())
            print("---")
    except: pass
    
    linie = []
    while True:
        l = input("> ")
        # Sprawdzamy czy wpisano słowo klucz
        if l.strip() == "ZAMKNIJ":
            break
        linie.append(l)
    
    if linie:
        try:
            with open(path, 'w', encoding='utf-8') as f:
                f.write("\n".join(linie))
            print("Zapisano.")
        except Exception as e: print(f"Błąd zapisu: {e}")
    else:
        print("Nie zapisano zmian (pusta treść lub od razu zamknięto).")

def cmd_usun(nazwa):
    if not nazwa: return
    path = os.path.join(CURRENT_PATH, nazwa)
    
    if OBECNY_ROLA == "gosc":
        if not path.startswith(os.path.join(BASE_PATH, "users", OBECNY_LOGIN)):
            print("Brak uprawnień.")
            return

    if not os.path.exists(path):
        print("Nie znaleziono.")
        return
    
    try:
        if os.path.isdir(path):
            shutil.rmtree(path)
            print("Usunięto folder.")
        else:
            os.remove(path)
            print("Usunięto plik.")
    except Exception as e: print(f"Błąd: {e}")

def cmd_ukryj(nazwa):
    if not nazwa: return
    src = os.path.join(CURRENT_PATH, nazwa)
    if nazwa.startswith("."): return
    dst = os.path.join(CURRENT_PATH, "." + nazwa)
    if os.path.exists(src):
        os.rename(src, dst)
        print(f"Ukryto: {nazwa}")
    else: print("Nie znaleziono.")

def cmd_pokaz(nazwa):
    if not nazwa: return
    hidden_name = "." + nazwa
    src = os.path.join(CURRENT_PATH, hidden_name)
    dst = os.path.join(CURRENT_PATH, nazwa)
    if os.path.exists(src):
        os.rename(src, dst)
        print(f"Odkryto: {nazwa}")
    else: print(f"Nie znaleziono ukrytego: {hidden_name}")

def cmd_otworz(nazwa):
    global CURRENT_PATH
    if not nazwa: return
    
    if nazwa == "..":
        parent = os.path.dirname(CURRENT_PATH)
        if os.path.commonpath([parent, BASE_PATH]) == BASE_PATH:
            if OBECNY_ROLA == "gosc":
                gosc_root = os.path.join(BASE_PATH, "users", OBECNY_LOGIN)
                if os.path.commonpath([parent, gosc_root]) != gosc_root:
                    print("Blokada wyjścia.")
                    return None
            CURRENT_PATH = parent
            return "BEZ_PAUZY"
        else:
            print("Jesteś w głównym katalogu.")
            return None

    target_path = os.path.join(CURRENT_PATH, nazwa)
    
    if not os.path.exists(target_path):
        hidden = os.path.join(CURRENT_PATH, "." + nazwa)
        if os.path.exists(hidden): target_path = hidden
        else:
            print("Nie znaleziono.")
            return None

    if os.path.isdir(target_path):
        CURRENT_PATH = target_path
        return "BEZ_PAUZY"
    
    elif os.path.isfile(target_path):
        if nazwa.endswith(".py"):
            print(f"{K.CZERWONY}>>> URUCHAMIANIE: {nazwa} >>>{K.RESET}")
            try:
                with open(target_path, 'r', encoding='utf-8') as f:
                    exec(f.read())
            except Exception as e:
                print(f"BŁĄD PROGRAMU: {e}")
            print(f"{K.CZERWONY}<<< ZAKOŃCZONO <<<{K.RESET}")
        else:
            print(f"{K.ZOLTY}--- ZAWARTOŚĆ PLIKU: {nazwa} ---{K.RESET}")
            try:
                with open(target_path, 'r', encoding='utf-8') as f:
                    print(f.read())
            except Exception as e:
                print(f"Błąd odczytu: {e}")
            print(f"{K.ZOLTY}------------------------------{K.RESET}")

# --- MENU USTAWIEŃ ---

def logika_ustawienia():
    while True:
        wyczysc_ekran()
        print(f"{K.ZOLTY}--- USTAWIENIA ---{K.RESET}")
        print("1. Konto")
        print("2. Kolory")
        print("0. Wroc")
        w = input("> ")
        if w=="0": break
        elif w=="2": 
            K.AKTYWNE = not K.AKTYWNE
            print("Przelaczono kolory.")
            time.sleep(0.5)
        elif w=="1":
            print("1. Dodaj Goscia (Admin)")
            print("2. Zmien Haslo")
            print("0. Wroc")
            sw = input("> ")
            if sw=="1":
                if OBECNY_ROLA != "admin":
                    print("Brak uprawnien.")
                    time.sleep(1); continue
                n = input("Nazwa goscia: ")
                h = input("Haslo: ")
                db = laduj_uzytkownikow()
                if n in db: print("Juz istnieje.")
                else:
                    user_folder = os.path.join(BASE_PATH, "users", n)
                    os.makedirs(user_folder, exist_ok=True)
                    db[n] = {"haslo": szyfruj(h), "rola": "gosc", "root_dir": f"/users/{n}"}
                    zapisz_uzytkownikow(db)
                    print("Dodano.")
                time.sleep(1)
            elif sw=="2":
                nh = input("Nowe haslo: ")
                db = laduj_uzytkownikow()
                db[OBECNY_LOGIN]["haslo"] = szyfruj(nh)
                zapisz_uzytkownikow(db)
                print("Zapisano.")
                time.sleep(1)

# --- MAIN ---

def main():
    global TRYB_POKAZ_UKRYTE
    inicjalizacja_systemu()
    
    while True:
        logowanie()
        while True:
            wyczysc_ekran()
            logo()
            pokaz_komendy()
            if TRYB_POKAZ_UKRYTE: print(f"{K.SZARY}[POKAZ UKRYTE]{K.RESET}")
            
            widok_pulpitu()
            
            rel_path = os.path.relpath(CURRENT_PATH, BASE_PATH)
            if rel_path == ".": rel_path = ""
            display_path = "/root" + ("/" + rel_path if rel_path else "")
            
            prompt = f"{K.CZERWONY}ComradeOS{K.RESET}:{K.ZOLTY}{display_path}{K.RESET}$ "
            
            try:
                l = input(prompt).strip()
                if TRYB_POKAZ_UKRYTE: TRYB_POKAZ_UKRYTE = False
                
                if not l: continue
                parts = l.split(maxsplit=1)
                cmd = parts[0].lower()
                arg = parts[1] if len(parts)>1 else None
                res = None

                if cmd == "zamknij": break
                elif cmd == "stworz-folder": cmd_stworz_folder(input("Nazwa: "))
                elif cmd == "utworz": cmd_utworz(arg if arg else input("Nazwa: "))
                elif cmd == "edytuj": cmd_edytuj(arg if arg else input("Nazwa: "))
                elif cmd == "usun": cmd_usun(arg if arg else input("Nazwa: "))
                elif cmd == "ukryj": cmd_ukryj(arg if arg else input("Nazwa: "))
                elif cmd == "pokaz": cmd_pokaz(arg if arg else input("Nazwa: "))
                elif cmd == "pokaz_ukryte": TRYB_POKAZ_UKRYTE = True; res = "BEZ_PAUZY"
                elif cmd == "otworz": res = cmd_otworz(arg if arg else input("Otworz: "))
                elif cmd == "wyjdz": res = cmd_otworz("..")
                elif cmd == "ustawienia": logika_ustawienia()
                else: print("Nieznana komenda.")
                
                if res != "BEZ_PAUZY": pauza()

            except KeyboardInterrupt: break
            except Exception as e: print(e); pauza()

if __name__ == "__main__":
    main()