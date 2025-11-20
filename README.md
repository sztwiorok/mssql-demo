# Setup Instructions

## Initial Setup

1. **Fork the repository:**  

   https://github.com/sztwiorok/mssql-demo

2. **Create a new project in Buddy** using your forked repository.

3. **Add a Windows Agent** to the project and install it on your MSSQL server.

4. **Copy the Agent Name** and create a project variable `AGENT_NAME` using this value **in lowercase**.

5. **Create a directory** on the Windows server for database migration files  

   e.g. `C:\Users\Administrator\mssql-demo`

6. **Add a project variable** `MIGRATIONS_PROJECT_PATH` with the path from the previous step.

---

## Database Configuration

1. **Run the Deploy pipeline** in Buddy.

2. **Create a database** named `MigrationTestDB` in MSSQL Server.

3. **Execute** `.\run_setup_user.ps1` on the Windows server from the migrations directory.

---

## Running Migrations

1. **Run the MigrateDB pipeline** in Buddy and select your desired version.  

   The pipeline will automatically apply migration scripts to your database, with rollback support when selecting a previous version.

