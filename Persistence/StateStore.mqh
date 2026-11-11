//+------------------------------------------------------------------+
//|                                         Persistence/StateStore    |
//|  Atomic text storage in the terminal's common folder.                |
//|                                                                   |
//|  Writes go to <name>.tmp and are moved over the real file only        |
//|  after a flush. Filesystem crash durability is not proven here.       |
//+------------------------------------------------------------------+
#ifndef __QME_PERSIST_STATESTORE_MQH__
#define __QME_PERSIST_STATESTORE_MQH__

#include "../Core/Types.mqh"
#include "../Core/Config.mqh"
#include "../Core/Utils.mqh"
#include "../Core/ErrorCodes.mqh"
#include "../Core/Logger.mqh"

class CStateStore
  {
private:
   bool              m_enabled;
   string            m_name;
   string            m_folder;
   long              m_writes;
   long              m_reads;
   long              m_failures;
   datetime          m_lastWrite;

   string            FullPath(const string name);

public:
                     CStateStore(void) { m_enabled = false; m_name = ""; m_folder = QME_STATE_FOLDER; m_writes = 0; m_reads = 0; m_failures = 0; m_lastWrite = 0; }
   bool              Init(const string name, const bool enabled, string &err);
   bool              Write(const string content, string &err);
   bool              Read(string &content, string &err);
   bool              Exists(void);
   bool              Remove(void);
   datetime          Modified(void);
   bool              Enabled(void) { return(m_enabled); }
   string            Name(void) { return(m_name); }
   long              Writes(void) { return(m_writes); }
   long              Reads(void) { return(m_reads); }
   long              Failures(void) { return(m_failures); }
   datetime          LastWrite(void) { return(m_lastWrite); }
   string            Describe(void);
  };

//------------------------------------------------------------------//
string CStateStore::FullPath(const string name)
  {
   return(m_folder + "\\" + name);
  }

//------------------------------------------------------------------//
bool CStateStore::Init(const string name, const bool enabled, string &err)
  {
   err = "";
   m_name = name;
   m_enabled = enabled;
   if(!enabled) return(true);

   if(StringLen(name) == 0)
     {
      err = "state store name is empty";
      m_enabled = false;
      return(false);
     }

   //--- the common folder must exist; create our subfolder once
   if(!FileIsExist(QME_STATE_FOLDER, FILE_COMMON))
     {
      if(!FolderCreate(QME_STATE_FOLDER, FILE_COMMON))
        {
         err = "cannot create state folder " + QME_STATE_FOLDER + " (" + QmeLastErrorText() + ")";
         m_enabled = false;
         return(false);
        }
     }
   return(true);
  }

//------------------------------------------------------------------//
bool CStateStore::Write(const string content, string &err)
  {
   err = "";
   if(!m_enabled) { err = "state store disabled"; return(false); }
   if(StringLen(content) == 0) { err = "refusing to write empty state"; return(false); }

   const string tmp = FullPath(m_name + ".tmp");
   const string dst = FullPath(m_name);

   const int h = FileOpen(tmp, FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON);
   if(h == INVALID_HANDLE)
     {
      err = "cannot open " + tmp + " (" + QmeLastErrorText() + ")";
      m_failures++;
      QmeLogMsg(QME_LOG_ERROR, "StateStore", err);
      return(false);
     }

   const bool ok = (FileWriteString(h, content) > 0);
   FileFlush(h);
   FileClose(h);

   if(!ok)
     {
      err = "write failed for " + tmp;
      m_failures++;
      FileDelete(tmp, FILE_COMMON);
      return(false);
     }

   //--- replace destination after writing the temporary file
   if(!FileMove(tmp, FILE_COMMON, dst, FILE_COMMON | FILE_REWRITE))
     {
      err = "cannot replace " + dst + " (" + QmeLastErrorText() + ")";
      m_failures++;
      FileDelete(tmp, FILE_COMMON);
      QmeLogMsg(QME_LOG_ERROR, "StateStore", err);
      return(false);
     }

   m_writes++;
   m_lastWrite = TimeCurrent();
   return(true);
  }

//------------------------------------------------------------------//
bool CStateStore::Read(string &content, string &err)
  {
   content = "";
   err = "";
   if(!m_enabled) { err = "state store disabled"; return(false); }

   const string path = FullPath(m_name);
   if(!FileIsExist(path, FILE_COMMON))
     {
      err = "no saved state (" + path + ")";
      return(false);
     }

   const int h = FileOpen(path, FILE_READ | FILE_TXT | FILE_ANSI | FILE_COMMON);
   if(h == INVALID_HANDLE)
     {
      err = "cannot open " + path + " (" + QmeLastErrorText() + ")";
      m_failures++;
      return(false);
     }

   const ulong size = FileSize(h);
   if(size == 0)
     {
      FileClose(h);
      err = "saved state is empty";
      m_failures++;
      return(false);
     }
   // FILE_TXT reads one line at a time, regardless of the length argument.
   // Compose emits line-oriented documents with a terminating newline.
   while(!FileIsEnding(h))
      content += FileReadString(h) + "\n";
   FileClose(h);

   m_reads++;
   if(StringLen(content) == 0)
     {
      err = "saved state is empty";
      return(false);
     }
   return(true);
  }

//------------------------------------------------------------------//
bool CStateStore::Exists(void)
  {
   if(!m_enabled) return(false);
   return(FileIsExist(FullPath(m_name), FILE_COMMON));
  }

bool CStateStore::Remove(void)
  {
   if(!m_enabled) return(false);
   if(!Exists()) return(true);
   return(FileDelete(FullPath(m_name), FILE_COMMON));
  }

//------------------------------------------------------------------//
datetime CStateStore::Modified(void)
  {
   if(!Exists()) return(0);
   const string path = FullPath(m_name);
   const int h = FileOpen(path, FILE_READ | FILE_TXT | FILE_ANSI | FILE_COMMON);
   if(h == INVALID_HANDLE) return(0);
   const datetime t = (datetime)FileGetInteger(h, FILE_MODIFY_DATE);
   FileClose(h);
   return(t);
  }

//------------------------------------------------------------------//
string CStateStore::Describe(void)
  {
   return("store " + m_name + (m_enabled ? "" : " (disabled)") +
          " writes=" + IntegerToString((int)m_writes) +
          " reads=" + IntegerToString((int)m_reads) +
          " failures=" + IntegerToString((int)m_failures) +
          (m_lastWrite > 0 ? " last=" + TimeToString(m_lastWrite, TIME_DATE | TIME_SECONDS) : ""));
  }

#endif // __QME_PERSIST_STATESTORE_MQH__
//+------------------------------------------------------------------+
